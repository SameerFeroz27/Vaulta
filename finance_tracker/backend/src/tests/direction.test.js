const {
  resolveDirection,
  getTypeConfidenceThreshold,
  TYPE_SOURCE,
  DEFAULT_TYPE_CONFIDENCE_THRESHOLD,
} = require('../services/direction');

// The threshold is read per call, so tests can vary it without reloading the module.
// Restore it afterwards so nothing leaks into the other test files.
const ORIGINAL_THRESHOLD = process.env.AI_TYPE_CONFIDENCE_THRESHOLD;

afterEach(() => {
  if (ORIGINAL_THRESHOLD === undefined) {
    delete process.env.AI_TYPE_CONFIDENCE_THRESHOLD;
  } else {
    process.env.AI_TYPE_CONFIDENCE_THRESHOLD = ORIGINAL_THRESHOLD;
  }
});

// ─── User override ───────────────────────────────────────────────

describe('resolveDirection — user override', () => {
  it('lets an explicit override win over a confident AI', () => {
    const result = resolveDirection({
      aiType: 'expense',
      aiTypeConfidence: 0.99,
      userOverride: 'income',
    });

    expect(result.type).toBe('income');
    expect(result.source).toBe(TYPE_SOURCE.USER_OVERRIDE);
    expect(result.needsReview).toBe(false);
  });

  it('does not hold an override for review even when the AI disagrees', () => {
    const result = resolveDirection({
      aiType: 'income',
      aiTypeConfidence: 0.95,
      hintsType: 'income',
      userOverride: 'expense',
    });

    expect(result.type).toBe('expense');
    expect(result.needsReview).toBe(false);
  });

  it('reports no confidence for an override, so it is not stored as if the AI were certain', () => {
    const result = resolveDirection({ userOverride: 'income' });
    expect(result.confidence).toBeNull();
  });

  it('treats a null override as auto mode and lets the AI decide', () => {
    const result = resolveDirection({
      aiType: 'income',
      aiTypeConfidence: 0.9,
      userOverride: null,
    });

    expect(result.type).toBe('income');
    expect(result.source).toBe(TYPE_SOURCE.AI_AUTO);
  });
});

// ─── AI decides ──────────────────────────────────────────────────

describe('resolveDirection — AI decides', () => {
  it('auto-files a confident AI direction', () => {
    const result = resolveDirection({ aiType: 'income', aiTypeConfidence: 0.92 });

    expect(result.type).toBe('income');
    expect(result.confidence).toBe(0.92);
    expect(result.needsReview).toBe(false);
  });

  it('holds a low-confidence AI direction for review', () => {
    const result = resolveDirection({ aiType: 'expense', aiTypeConfidence: 0.4 });

    expect(result.type).toBe('expense');
    expect(result.needsReview).toBe(true);
  });

  it('holds a direction with no confidence at all for review', () => {
    const result = resolveDirection({ aiType: 'income' });

    expect(result.type).toBe('income');
    expect(result.confidence).toBe(0);
    expect(result.needsReview).toBe(true);
  });

  it('falls back to overall extraction confidence when typeConfidence is omitted', () => {
    const result = resolveDirection({ aiType: 'income', aiConfidence: 0.88 });

    expect(result.confidence).toBe(0.88);
    expect(result.needsReview).toBe(false);
  });

  it('prefers typeConfidence over overall confidence', () => {
    const result = resolveDirection({
      aiType: 'income',
      aiTypeConfidence: 0.3,
      aiConfidence: 0.95,
    });

    expect(result.confidence).toBe(0.3);
    expect(result.needsReview).toBe(true);
  });
});

// ─── No AI direction ─────────────────────────────────────────────

describe('resolveDirection — AI gave no direction', () => {
  it('flags review instead of silently filing an expense', () => {
    const result = resolveDirection({});

    expect(result.type).toBe('expense'); // last-resort guess, but never silent
    expect(result.needsReview).toBe(true);
    expect(result.confidence).toBe(0);
  });

  it('uses the keyword hint as the best guess for a bank message', () => {
    const result = resolveDirection({ hintsType: 'income' });

    expect(result.type).toBe('income');
    expect(result.needsReview).toBe(true);
  });

  it('ignores an invalid AI type value', () => {
    const result = resolveDirection({ aiType: 'transfer' });
    expect(result.needsReview).toBe(true);
  });
});

// ─── Keyword cross-check ─────────────────────────────────────────

describe('resolveDirection — keyword cross-check', () => {
  it('holds a direction whose keyword hints contradict the AI', () => {
    const result = resolveDirection({
      aiType: 'expense',
      aiTypeConfidence: 0.95,
      hintsType: 'income',
    });

    // Still the AI's answer, but flagged: one of the two signals is wrong.
    expect(result.type).toBe('expense');
    expect(result.needsReview).toBe(true);
  });

  it('does not flag review when the hints agree', () => {
    const result = resolveDirection({
      aiType: 'income',
      aiTypeConfidence: 0.9,
      hintsType: 'income',
    });

    expect(result.needsReview).toBe(false);
  });

  it('ignores hints for image receipts, which carry none', () => {
    const result = resolveDirection({ aiType: 'expense', aiTypeConfidence: 0.9 });

    expect(result.needsReview).toBe(false);
  });
});

// ─── Threshold configuration ─────────────────────────────────────

describe('getTypeConfidenceThreshold', () => {
  it('defaults when unset', () => {
    delete process.env.AI_TYPE_CONFIDENCE_THRESHOLD;
    expect(getTypeConfidenceThreshold()).toBe(DEFAULT_TYPE_CONFIDENCE_THRESHOLD);
  });

  it('reads the configured value', () => {
    process.env.AI_TYPE_CONFIDENCE_THRESHOLD = '0.5';
    expect(getTypeConfidenceThreshold()).toBe(0.5);
  });

  it('falls back to the default on a non-numeric value', () => {
    process.env.AI_TYPE_CONFIDENCE_THRESHOLD = 'not-a-number';
    expect(getTypeConfidenceThreshold()).toBe(DEFAULT_TYPE_CONFIDENCE_THRESHOLD);
  });

  it('changes whether a given confidence is auto-filed', () => {
    process.env.AI_TYPE_CONFIDENCE_THRESHOLD = '0.9';
    expect(resolveDirection({ aiType: 'income', aiTypeConfidence: 0.8 }).needsReview).toBe(true);

    process.env.AI_TYPE_CONFIDENCE_THRESHOLD = '0.5';
    expect(resolveDirection({ aiType: 'income', aiTypeConfidence: 0.8 }).needsReview).toBe(false);
  });
});
