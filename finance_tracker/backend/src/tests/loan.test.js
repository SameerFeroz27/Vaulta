const {
  DIRECTION,
  STATE,
  KIND,
  sumPaid,
  outstanding,
  surplus,
  state,
  isOverdue,
  movementType,
  describeLoan,
} = require('../services/loan');

// ─── sumPaid ─────────────────────────────────────────────────────

describe('sumPaid', () => {
  it('sums payment rows', () => {
    expect(sumPaid([{ amount: '1000.50' }, { amount: '2500.25' }])).toBe(3500.75);
  });

  it('sums bare numbers', () => {
    expect(sumPaid([100, 200])).toBe(300);
  });

  it('returns 0 for no payments', () => {
    expect(sumPaid([])).toBe(0);
    expect(sumPaid()).toBe(0);
  });
});

// ─── outstanding ─────────────────────────────────────────────────

describe('outstanding', () => {
  it('is the principal minus what has been repaid', () => {
    expect(outstanding(50000, 20000)).toBe(30000);
  });

  it('is the full principal before any repayment', () => {
    expect(outstanding(50000, 0)).toBe(50000);
  });

  it('is zero once fully repaid', () => {
    expect(outstanding(50000, 50000)).toBe(0);
  });

  it('floors at zero when overpaid instead of going negative', () => {
    expect(outstanding(50000, 60000)).toBe(0);
  });
});

// ─── surplus ─────────────────────────────────────────────────────

describe('surplus', () => {
  it('is zero while the loan is unpaid', () => {
    expect(surplus(50000, 20000)).toBe(0);
  });

  it('is zero exactly at the principal', () => {
    expect(surplus(50000, 50000)).toBe(0);
  });

  it('reports the excess when overpaid, for the gift/tip/refund label', () => {
    expect(surplus(50000, 60000)).toBe(10000);
  });
});

// ─── state ───────────────────────────────────────────────────────

describe('state', () => {
  it('is open while anything is still owed', () => {
    expect(state(50000, 49999)).toBe(STATE.OPEN);
    expect(state(50000, 0)).toBe(STATE.OPEN);
  });

  it('settles exactly at the principal', () => {
    expect(state(50000, 50000)).toBe(STATE.SETTLED);
  });

  it('stays settled when overpaid', () => {
    expect(state(50000, 60000)).toBe(STATE.SETTLED);
  });
});

// ─── isOverdue ───────────────────────────────────────────────────

describe('isOverdue', () => {
  const today = new Date('2026-06-15T00:00:00Z');

  it('is false with no due date', () => {
    expect(isOverdue(null, STATE.OPEN, today)).toBe(false);
  });

  it('is true when past due and open', () => {
    expect(isOverdue('2026-06-01', STATE.OPEN, today)).toBe(true);
  });

  it('is false when due in the future', () => {
    expect(isOverdue('2026-07-01', STATE.OPEN, today)).toBe(false);
  });

  it('is false on the due date itself', () => {
    expect(isOverdue('2026-06-15', STATE.OPEN, today)).toBe(false);
  });

  it('is false for a settled loan however late it was', () => {
    expect(isOverdue('2026-01-01', STATE.SETTLED, today)).toBe(false);
  });

  it('accepts a Date or a timestamp for the due date', () => {
    expect(isOverdue(new Date('2026-06-01T00:00:00Z'), STATE.OPEN, today)).toBe(true);
    expect(isOverdue('2026-06-01T00:00:00.000Z', STATE.OPEN, today)).toBe(true);
  });
});

// ─── movementType ────────────────────────────────────────────────

describe('movementType', () => {
  it('lending money out is an outflow', () => {
    expect(movementType(DIRECTION.LENT, KIND.DISBURSEMENT)).toBe('expense');
  });

  it('being repaid is an inflow', () => {
    expect(movementType(DIRECTION.LENT, KIND.REPAYMENT)).toBe('income');
  });

  it('borrowing is the exact mirror: money in', () => {
    expect(movementType(DIRECTION.BORROWED, KIND.DISBURSEMENT)).toBe('income');
  });

  it('repaying a borrowed loan is money out', () => {
    expect(movementType(DIRECTION.BORROWED, KIND.REPAYMENT)).toBe('expense');
  });
});

// ─── describeLoan ────────────────────────────────────────────────

describe('describeLoan', () => {
  it('describes a partly repaid loan', () => {
    const result = describeLoan({ principal: '50000', dueDate: '2026-01-01' }, 20000);

    expect(result.paid).toBe(20000);
    expect(result.outstanding).toBe(30000);
    expect(result.surplus).toBe(0);
    expect(result.state).toBe(STATE.OPEN);
  });

  it('describes an overpaid loan as settled with a surplus', () => {
    const result = describeLoan({ principal: '50000', dueDate: null }, 60000);

    expect(result.outstanding).toBe(0);
    expect(result.surplus).toBe(10000);
    expect(result.state).toBe(STATE.SETTLED);
    expect(result.overdue).toBe(false);
  });

  it('flags a past-due open loan as overdue', () => {
    const result = describeLoan({ principal: '50000', dueDate: '2020-01-01' }, 0);

    expect(result.overdue).toBe(true);
  });
});
