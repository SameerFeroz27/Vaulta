/**
 * Loan money rules.
 *
 * Outstanding, settled-ness and overpayment are all DERIVED here rather than stored,
 * so a loan's figures can never contradict its own repayment history and concurrent
 * repayments cannot race a cached balance.
 *
 * Deliberately free of database access so the awkward cases — partial repayment,
 * overpayment, overdue — are unit-testable without Postgres.
 */

/** Which way the money went. `lent` = they owe me, `borrowed` = I owe them. */
const DIRECTION = { LENT: 'lent', BORROWED: 'borrowed' };

/** Derived, never stored. */
const STATE = { OPEN: 'open', SETTLED: 'settled' };

/** Marks transactions this feature created, so reports can exclude them. */
const KIND = { DISBURSEMENT: 'loan_disbursement', REPAYMENT: 'loan_repayment' };

/** Money is numeric(14,2) in the database; keep JS arithmetic at the same precision. */
function round2(value) {
  return Math.round((Number(value) + Number.EPSILON) * 100) / 100;
}

function toNumber(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

/**
 * Total repaid against a loan.
 * Accepts either payment rows (`{ amount }`) or bare numbers.
 */
function sumPaid(payments = []) {
  return round2(
    payments.reduce((total, payment) => total + toNumber(payment?.amount ?? payment), 0)
  );
}

/**
 * What is still owed. Floors at zero: overpaying settles the loan rather than
 * producing a negative balance, and the excess is reported separately as `surplus`.
 */
function outstanding(principal, paid) {
  return round2(Math.max(0, toNumber(principal) - toNumber(paid)));
}

/**
 * Anything repaid beyond the principal — presented to the user as a gift, tip or
 * refund rather than being rejected as an error.
 */
function surplus(principal, paid) {
  return round2(Math.max(0, toNumber(paid) - toNumber(principal)));
}

/** A loan is settled once repayments reach the principal. */
function state(principal, paid) {
  return toNumber(paid) >= toNumber(principal) ? STATE.SETTLED : STATE.OPEN;
}

/** Normalise a date (Date | 'YYYY-MM-DD' | timestamp string) to YYYY-MM-DD. */
function toDateString(value) {
  if (!value) return null;
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
}

/**
 * Past its due date and still open. A loan with no due date is never overdue, and a
 * settled loan never is, however late it was.
 */
function isOverdue(dueDate, loanState, today = new Date()) {
  const due = toDateString(dueDate);
  if (!due || loanState === STATE.SETTLED) return false;
  // Both sides are YYYY-MM-DD, so a string compare is a correct date compare.
  return due < toDateString(today);
}

/**
 * Which way the cash physically moved, as a transaction type.
 *
 * Lending money out is money gone; being repaid is money back. Borrowing is the exact
 * mirror: receiving the loan is money in, repaying it is money out.
 *
 * @param {'lent'|'borrowed'} direction
 * @param {'loan_disbursement'|'loan_repayment'} kind
 * @returns {'expense'|'income'}
 */
function movementType(direction, kind) {
  const isLent = direction === DIRECTION.LENT;
  const isDisbursement = kind === KIND.DISBURSEMENT;
  const isOutflow = isDisbursement ? isLent : !isLent;
  return isOutflow ? 'expense' : 'income';
}

/**
 * Attach every derived field to a loan row.
 * @param {object} loan - row with at least `principal` and `dueDate`
 * @param {number|string} paid - total repaid
 * @returns {{paid: number, outstanding: number, surplus: number, state: string, overdue: boolean}}
 */
function describeLoan(loan, paid) {
  const paidTotal = round2(toNumber(paid));
  const principal = toNumber(loan.principal);
  const loanState = state(principal, paidTotal);

  return {
    paid: paidTotal,
    outstanding: outstanding(principal, paidTotal),
    surplus: surplus(principal, paidTotal),
    state: loanState,
    overdue: isOverdue(loan.dueDate, loanState),
  };
}

module.exports = {
  DIRECTION,
  STATE,
  KIND,
  round2,
  sumPaid,
  outstanding,
  surplus,
  state,
  isOverdue,
  movementType,
  describeLoan,
  toDateString,
};
