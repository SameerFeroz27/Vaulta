/**
 * Bank message pre-processing.
 * Extracts structured hints (amount, date, card last-4, type) from raw bank SMS
 * using regex patterns before sending to the AI for full parsing.
 * This gives the AI structured context to improve accuracy.
 */

// Common patterns across different bank SMS formats.
// The amount group tolerates a leading minus ("Rs. -1,500"), which would
// otherwise fall through to the decimals-only pattern and be missed entirely.
const AMOUNT_PATTERNS = [
  /(?:PKR|Rs\.?)\s*(-[\d,]*\.?\d+|[\d,]+\.?\d*)/i,
  /(?:amount|amt)\s*[:\s]*(-[\d,]*\.?\d+|[\d,]+\.?\d*)/i,
  /(-[\d,]+\.\d{2}|[\d,]+\.\d{2})/,
];

const CARD_PATTERNS = [
  /card\s*(?:ending)?\s*(?:with)?\s*\*{0,4}(\d{4})/i,
  /\*{4}(\d{4})/,
  /xx{0,4}(\d{4})/i,
  /card\s*no\.?\s*\*{0,4}(\d{4})/i,
];

const DATE_PATTERNS = [
  /(\d{4}-\d{2}-\d{2})/,
  /(\d{1,2}[\/-]\d{1,2}[\/-]\d{2,4})/,
];

const TIME_PATTERNS = [
  /(\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM)?)/i,
];

// Debit → expense; credit → income.
// Tested as word-boundary regexes rather than substrings: `includes('used')`
// used to fire on "unused" and "caused". Direction-specific phrases come first
// so "transferred to" (expense) is not matched by a bare "transferred".
const DEBIT_PATTERNS = [
  /\byou (?:have )?sent\b/,
  /\bsent to\b/,
  /\btransferred to\b/,
  /\bpaid to\b/,
  /\bdebited\b/,
  /\bspent\b/,
  /\bwithdrawn\b/,
  /\bwithdrawal\b/,
  /\bpurchased?\b/,
  /\bcharged\b/,
  /\bpos\b/,
  /\batm\b/,
  /\bsent\b/,
];

const CREDIT_PATTERNS = [
  /\byou (?:have )?received\b/,
  /\breceived from\b/,
  /\btransferred from\b/,
  /\bcredited\b/,
  /\bdeposited\b/,
  /\brefund(?:ed)?\b/,
  /\breversal\b/,
  /\bsalary\b/,
  /\bcash ?back\b/,
  /\breceived\b/,
];

/** Uppercase CR/DR markers are explicit, so they are matched case-sensitively. */
const CR_MARKER = /\bCR\b/;
const DR_MARKER = /\bDR\b/;

/**
 * Extract structured hints from a bank SMS message.
 * @param {string} message - Raw bank SMS text
 * @returns {object} Extracted hints: { amount, amountNegative, cardLast4, date, time, type, confidence }
 */
function parseBankMessage(message) {
  if (!message || typeof message !== 'string') {
    return { confidence: 0 };
  }

  const hints = { confidence: 0 };
  const lowerMsg = message.toLowerCase();

  // Extract amount
  for (const pattern of AMOUNT_PATTERNS) {
    const match = message.match(pattern);
    if (match && match[1]) {
      const value = parseFloat(match[1].replace(/,/g, ''));
      if (Number.isFinite(value)) {
        hints.amount = Math.abs(value);
        // A signed amount is a debit signal in itself (e.g. "Rs. -1,500").
        if (value < 0) hints.amountNegative = true;
        hints.confidence += 0.3;
        break;
      }
    }
  }

  // Extract card last 4
  for (const pattern of CARD_PATTERNS) {
    const match = message.match(pattern);
    if (match && match[1]) {
      hints.cardLast4 = match[1];
      hints.confidence += 0.2;
      break;
    }
  }

  // Extract date
  for (const pattern of DATE_PATTERNS) {
    const match = message.match(pattern);
    if (match && match[1]) {
      hints.date = match[1];
      hints.confidence += 0.2;
      break;
    }
  }

  // Extract time
  for (const pattern of TIME_PATTERNS) {
    const match = message.match(pattern);
    if (match && match[1]) {
      hints.time = match[1];
      hints.confidence += 0.1;
      break;
    }
  }

  // Determine type (debit = expense, credit = income). When the message carries
  // signals in both directions the hint is left unset rather than guessed, so the
  // AI decides unaided and resolveDirection() sees no hint to cross-check.
  const isDebit =
    DEBIT_PATTERNS.some((pattern) => pattern.test(lowerMsg)) ||
    DR_MARKER.test(message) ||
    hints.amountNegative === true;
  const isCredit =
    CREDIT_PATTERNS.some((pattern) => pattern.test(lowerMsg)) ||
    CR_MARKER.test(message);

  if (isDebit && !isCredit) {
    hints.type = 'expense';
    hints.confidence += 0.2;
  } else if (isCredit && !isDebit) {
    hints.type = 'income';
    hints.confidence += 0.2;
  }

  return hints;
}

/**
 * System prompt for bank-SMS extraction. Defined here beside buildAiPrompt so both
 * halves of the bank prompt live together and can be exercised by tests.
 */
const BANK_MESSAGE_SYSTEM_PROMPT = `You are a bank transaction parser. Extract the transaction details from the bank message and return ONLY a valid JSON object with these fields:
- merchant: string (merchant or description)
- amount: number (transaction amount, positive)
- total: number (same as amount)
- date: string (YYYY-MM-DD format if available)
- type: string ("expense" for a debit/money sent, "income" for a credit/money received)
- typeConfidence: number (0-1, your confidence specifically in the type)
- directionEvidence: string (the exact words in the message that justify the type)
- cardLast4: string (last 4 digits of card if mentioned)
- bankReference: string (transaction reference number if available)
- description: string (additional details)
- confidence: number (0-1)

Bank messages describe the movement from the account holder's point of view: "you sent" / "debited" / "withdrawn" mean expense; "you received" / "credited" / "refund" mean income.

If the message gives no reliable signal for income vs expense, OMIT the type, typeConfidence and directionEvidence fields. Do not guess, and do not default to expense.

If a field is not present, omit it. Always return valid JSON.`;

/**
 * Build a structured prompt for the AI using the extracted hints.
 * @param {string} message - Raw bank SMS
 * @param {object} hints - Pre-extracted hints
 * @returns {string} Formatted prompt for the AI
 */
function buildAiPrompt(message, hints) {
  const hintLines = [];
  if (hints.amount) hintLines.push(`- Pre-extracted amount: ${hints.amount}`);
  if (hints.cardLast4) hintLines.push(`- Card last 4 digits: ${hints.cardLast4}`);
  if (hints.date) hintLines.push(`- Date: ${hints.date}`);
  if (hints.time) hintLines.push(`- Time: ${hints.time}`);
  // hints.type is deliberately NOT sent: it is the independent signal that
  // resolveDirection() cross-checks the AI against, so the AI must not see it.

  const hintsSection = hintLines.length > 0
    ? `\n\nPre-extracted hints (verify and use these if correct):\n${hintLines.join('\n')}`
    : '';

  return `You are a financial transaction parser. Extract the transaction details from the following bank message and return ONLY a valid JSON object with these fields:
- merchant: string (the merchant or description of the transaction)
- amount: number (the transaction amount, positive)
- total: number (same as amount for bank messages)
- date: string (transaction date in YYYY-MM-DD format if available)
- time: string (transaction time if available)
- type: string ("expense" for a debit/money sent, "income" for a credit/money received)
- typeConfidence: number (0-1, your confidence specifically in the type)
- directionEvidence: string (the exact words in the message that justify the type)
- cardLast4: string (last 4 digits of card if mentioned)
- bankReference: string (any transaction reference number)
- description: string (additional details if any)
- confidence: number (0-1, your confidence in the extraction)

Deciding the type — bank messages describe the movement from the account holder's point of view:
- "expense": the account holder sent or spent money. Cues: "you sent", "debited", "spent", "withdrawn", "paid", "transferred to", "purchase".
- "income": the account holder received money. Cues: "you received", "credited", "deposited", "refund", "reversal", "salary", "transferred from".
- Set directionEvidence to the short phrase you relied on, e.g. "message says 'you sent'".

If the message gives no reliable signal for income vs expense, OMIT the type, typeConfidence and directionEvidence fields entirely. Do not guess, and do not default to expense.

Bank message:
${message}${hintsSection}`;
}

module.exports = { parseBankMessage, buildAiPrompt, BANK_MESSAGE_SYSTEM_PROMPT };
