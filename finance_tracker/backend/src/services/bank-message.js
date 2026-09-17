/**
 * Bank message pre-processing.
 * Extracts structured hints (amount, date, card last-4, type) from raw bank SMS
 * using regex patterns before sending to the AI for full parsing.
 * This gives the AI structured context to improve accuracy.
 */

// Common patterns across different bank SMS formats
const AMOUNT_PATTERNS = [
  /(?:PKR|Rs\.?|RS\.?|rs)\s*([\d,]+\.?\d*)/i,
  /(?:amount|amt)\s*[:\s]*\s*([\d,]+\.?\d*)/i,
  /([\d,]+\.\d{2})/,
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

// Debit keywords → expense; Credit keywords → income
const DEBIT_KEYWORDS = ['spent', 'debited', 'purchased', 'paid', 'withdrawn', 'used', 'charged'];
const CREDIT_KEYWORDS = ['credited', 'received', 'deposited', 'refund', 'reversal', 'salary'];

/**
 * Extract structured hints from a bank SMS message.
 * @param {string} message - Raw bank SMS text
 * @returns {object} Extracted hints: { amount, cardLast4, date, time, type, confidence }
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
      hints.amount = parseFloat(match[1].replace(/,/g, ''));
      hints.confidence += 0.3;
      break;
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

  // Determine type (debit = expense, credit = income)
  if (DEBIT_KEYWORDS.some((kw) => lowerMsg.includes(kw))) {
    hints.type = 'expense';
    hints.confidence += 0.2;
  } else if (CREDIT_KEYWORDS.some((kw) => lowerMsg.includes(kw))) {
    hints.type = 'income';
    hints.confidence += 0.2;
  }

  return hints;
}

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
  if (hints.type) hintLines.push(`- Transaction type: ${hints.type}`);

  const hintsSection = hintLines.length > 0
    ? `\n\nPre-extracted hints (verify and use these if correct):\n${hintLines.join('\n')}`
    : '';

  return `You are a financial transaction parser. Extract the transaction details from the following bank message and return ONLY a valid JSON object with these fields:
- merchant: string (the merchant or description of the transaction)
- amount: number (the transaction amount, positive)
- total: number (same as amount for bank messages)
- date: string (transaction date in YYYY-MM-DD format if available)
- time: string (transaction time if available)
- type: string ("expense" for debit/spent, "income" for credit/received)
- cardLast4: string (last 4 digits of card if mentioned)
- bankReference: string (any transaction reference number)
- description: string (additional details if any)
- confidence: number (0-1, your confidence in the extraction)

Bank message:
${message}${hintsSection}`;
}

module.exports = { parseBankMessage, buildAiPrompt };
