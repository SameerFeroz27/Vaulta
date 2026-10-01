/**
 * Transaction direction resolution (income vs expense).
 *
 * Replaces the old `userOverride || aiType || 'expense'` fallback chain, which
 * silently collapsed "the AI said expense", "the AI said nothing" and "the AI
 * failed" into the same outcome — an expense.
 *
 * Direction is resolved from the strongest available signal: an explicit user
 * override wins outright, otherwise the AI's judgement is used and cross-checked
 * against the bank-SMS keyword hints. Anything short of confident is flagged for
 * one-tap review rather than guessed at.
 */

const DEFAULT_TYPE_CONFIDENCE_THRESHOLD = 0.7;

/** Where a transaction's direction came from. Mirrors transactions.type_source. */
const TYPE_SOURCE = {
  USER_OVERRIDE: 'user_override',
  AI_AUTO: 'ai_auto',
  MANUAL: 'manual',
};

/**
 * Read the threshold per call so tests can vary it without reloading the module.
 * Follows the project's inline process.env convention (no central config module).
 */
function getTypeConfidenceThreshold() {
  const parsed = parseFloat(process.env.AI_TYPE_CONFIDENCE_THRESHOLD);
  return Number.isFinite(parsed) ? parsed : DEFAULT_TYPE_CONFIDENCE_THRESHOLD;
}

function clamp01(value) {
  if (typeof value !== 'number' || Number.isNaN(value)) return 0;
  return Math.min(1, Math.max(0, value));
}

/**
 * Resolve the direction of a parsed transaction.
 *
 * @param {object} input
 * @param {'income'|'expense'} [input.aiType] - Direction the AI inferred.
 * @param {number} [input.aiTypeConfidence] - AI's confidence in that direction (0-1).
 * @param {number} [input.aiConfidence] - Overall extraction confidence, used as a
 *   weaker proxy when the model omits typeConfidence and returns a bare type.
 * @param {'income'|'expense'} [input.hintsType] - Direction from bank-SMS keyword hints.
 * @param {'income'|'expense'|null} [input.userOverride] - Explicit user choice.
 * @returns {{ type: 'income'|'expense', confidence: number|null, source: string, needsReview: boolean }}
 *   confidence is the AI's confidence in the inferred direction, or null when the
 *   direction did not come from the AI (an override), so it is never stored as if
 *   the model had been certain.
 */
function resolveDirection({
  aiType,
  aiTypeConfidence,
  aiConfidence,
  hintsType,
  userOverride,
} = {}) {
  // An explicit choice from the user is final — never second-guessed.
  if (userOverride === 'income' || userOverride === 'expense') {
    return {
      type: userOverride,
      confidence: null,
      source: TYPE_SOURCE.USER_OVERRIDE,
      needsReview: false,
    };
  }

  // The AI returned no direction. Fall back to the keyword hints, then to expense,
  // but always flag it: this is the case that used to be filed silently.
  if (aiType !== 'income' && aiType !== 'expense') {
    return {
      type: hintsType === 'income' || hintsType === 'expense' ? hintsType : 'expense',
      confidence: 0,
      source: TYPE_SOURCE.AI_AUTO,
      needsReview: true,
    };
  }

  const confidence = clamp01(aiTypeConfidence ?? aiConfidence ?? 0);

  // A keyword hint contradicting the AI means one of the two is wrong. Bank
  // messages are the only input carrying hints, so this never fires for images.
  const hintsDisagree = (hintsType === 'income' || hintsType === 'expense') && hintsType !== aiType;

  return {
    type: aiType,
    confidence,
    source: TYPE_SOURCE.AI_AUTO,
    needsReview: hintsDisagree || confidence < getTypeConfidenceThreshold(),
  };
}

module.exports = {
  resolveDirection,
  getTypeConfidenceThreshold,
  DEFAULT_TYPE_CONFIDENCE_THRESHOLD,
  TYPE_SOURCE,
};
