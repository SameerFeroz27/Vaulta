const {
  stripMarkdownFences,
  safeJsonParse,
  parseAndValidateAiOutput,
} = require('../validators/ai-output.schema');
const { parseBankMessage, buildAiPrompt, sanitizeBankMerchant, BANK_MESSAGE_SYSTEM_PROMPT } = require('../services/bank-message');
const bankSmsFixtures = require('./fixtures/bank-sms.json');

// ─── stripMarkdownFences ─────────────────────────────────────────

describe('stripMarkdownFences', () => {
  it('should strip ```json fences', () => {
    const input = '```json\n{"merchant": "Test"}\n```';
    expect(stripMarkdownFences(input)).toBe('{"merchant": "Test"}');
  });

  it('should strip ```JSON fences (uppercase)', () => {
    const input = '```JSON\n{"merchant": "Test"}\n```';
    expect(stripMarkdownFences(input)).toBe('{"merchant": "Test"}');
  });

  it('should strip plain ``` fences', () => {
    const input = '```\n{"merchant": "Test"}\n```';
    expect(stripMarkdownFences(input)).toBe('{"merchant": "Test"}');
  });

  it('should pass through plain JSON unchanged', () => {
    const input = '{"merchant": "Test"}';
    expect(stripMarkdownFences(input)).toBe('{"merchant": "Test"}');
  });

  it('should handle null/empty input', () => {
    expect(stripMarkdownFences(null)).toBeNull();
    expect(stripMarkdownFences('')).toBe('');
  });
});

// ─── safeJsonParse ────────────────────────────────────────────────

describe('safeJsonParse', () => {
  it('should parse valid JSON', () => {
    const result = safeJsonParse('{"amount": 100}');
    expect(result.success).toBe(true);
    expect(result.data.amount).toBe(100);
  });

  it('should parse JSON wrapped in markdown fences', () => {
    const result = safeJsonParse('```json\n{"amount": 100}\n```');
    expect(result.success).toBe(true);
    expect(result.data.amount).toBe(100);
  });

  it('should extract JSON from surrounding prose', () => {
    const result = safeJsonParse('Here is the result:\n{"amount": 100}\nDone.');
    expect(result.success).toBe(true);
    expect(result.data.amount).toBe(100);
  });

  it('should fail on invalid JSON', () => {
    const result = safeJsonParse('This is not JSON at all');
    expect(result.success).toBe(false);
    expect(result.error).toBeDefined();
  });

  it('should fail on empty string', () => {
    const result = safeJsonParse('');
    expect(result.success).toBe(false);
  });

  it('should fail on null', () => {
    const result = safeJsonParse(null);
    expect(result.success).toBe(false);
  });
});

// ─── parseAndValidateAiOutput ─────────────────────────────────────

describe('parseAndValidateAiOutput', () => {
  it('should validate a complete valid receipt JSON', () => {
    const input = JSON.stringify({
      merchant: 'KFC',
      amount: 1250.50,
      total: 1250.50,
      subtotal: 1100.00,
      tax: 150.50,
      date: '2024-01-15',
      time: '14:30',
      currency: 'PKR',
      type: 'expense',
      items: [
        { name: 'Zinger Burger', quantity: 2, price: 550 },
        { name: 'Fries', quantity: 1, price: 0 },
      ],
      confidence: 0.95,
    });

    const result = parseAndValidateAiOutput(input);
    expect(result.success).toBe(true);
    expect(result.data.merchant).toBe('KFC');
    expect(result.data.amount).toBe(1250.50);
    expect(result.data.items).toHaveLength(2);
  });

  it('should validate JSON wrapped in markdown fences', () => {
    const input = '```json\n{"merchant": "Test Store", "amount": 500, "type": "expense"}\n```';
    const result = parseAndValidateAiOutput(input);
    expect(result.success).toBe(true);
    expect(result.data.merchant).toBe('Test Store');
  });

  it('should validate JSON with extra prose around it', () => {
    const input = 'I extracted the following:\n{"merchant": "Store", "amount": 200}\nHope this helps!';
    const result = parseAndValidateAiOutput(input);
    expect(result.success).toBe(true);
    expect(result.data.merchant).toBe('Store');
  });

  it('should fail on completely invalid text', () => {
    const result = parseAndValidateAiOutput('The receipt is unreadable');
    expect(result.success).toBe(false);
    expect(result.error).toBeDefined();
  });

  it('should apply defaults for missing optional fields', () => {
    const input = '{"amount": 100}';
    const result = parseAndValidateAiOutput(input);
    expect(result.success).toBe(true);
    expect(result.data.merchant).toBe('Unknown');
  });

  it('should leave type undefined when the AI omits it', () => {
    // This used to default to 'expense', which silently misfiled an income receipt the
    // AI could not read. It must stay absent so the worker can route it to review.
    const input = '{"amount": 100, "merchant": "Store"}';
    const result = parseAndValidateAiOutput(input);
    expect(result.success).toBe(true);
    expect(result.data.type).toBeUndefined();
  });

  it('should accept typeConfidence and directionEvidence', () => {
    const input = JSON.stringify({
      amount: 100,
      type: 'income',
      typeConfidence: 0.82,
      directionEvidence: "header says 'REFUND RECEIPT'",
    });
    const result = parseAndValidateAiOutput(input);

    expect(result.success).toBe(true);
    expect(result.data.type).toBe('income');
    expect(result.data.typeConfidence).toBe(0.82);
    expect(result.data.directionEvidence).toBe("header says 'REFUND RECEIPT'");
  });
});

// ─── parseBankMessage ─────────────────────────────────────────────

describe('parseBankMessage', () => {
  it('should extract amount from a typical debit SMS', () => {
    const msg = 'Your card ending 1234 has been charged. PKR 1,500.00 spent at KFC on 15/01/2024 14:30. Available balance: PKR 50,000.';
    const hints = parseBankMessage(msg);

    expect(hints.amount).toBe(1500.00);
    expect(hints.cardLast4).toBe('1234');
    expect(hints.type).toBe('expense');
    expect(hints.confidence).toBeGreaterThan(0);
  });

  it('should detect credit transaction type', () => {
    const msg = 'PKR 50,000.00 has been credited to your account on 2024-01-15. Available balance: PKR 100,000.';
    const hints = parseBankMessage(msg);

    expect(hints.amount).toBe(50000.00);
    expect(hints.type).toBe('income');
  });

  it('should extract date from DD/MM/YYYY format', () => {
    const msg = 'PKR 500 spent on 15/01/2024 at Store';
    const hints = parseBankMessage(msg);
    expect(hints.date).toBe('15/01/2024');
  });

  it('should extract date from YYYY-MM-DD format', () => {
    const msg = 'PKR 500 spent on 2024-01-15 at Store';
    const hints = parseBankMessage(msg);
    expect(hints.date).toBe('2024-01-15');
  });

  it('should return low confidence for empty message', () => {
    const hints = parseBankMessage('');
    expect(hints.confidence).toBe(0);
  });

  it('should handle null input gracefully', () => {
    const hints = parseBankMessage(null);
    expect(hints.confidence).toBe(0);
  });
});

// ─── parseBankMessage against real bank SMS formats ───────────────

describe('parseBankMessage — bank SMS fixtures', () => {
  for (const sample of bankSmsFixtures.cases) {
    it(`${sample.bank}: ${sample.name}`, () => {
      const hints = parseBankMessage(sample.message);
      // undefined means "no usable signal"; normalise so the fixture can say null.
      expect(hints.type ?? null).toBe(sample.expectedType);
    });
  }

  it('always extracts a positive amount, even from a signed value', () => {
    const signed = bankSmsFixtures.cases.find((c) => c.name.startsWith('Signed negative'));
    const hints = parseBankMessage(signed.message);

    expect(hints.amount).toBe(1500);
    expect(hints.amount).toBeGreaterThan(0);
  });
});

// ─── buildAiPrompt ────────────────────────────────────────────────

describe('buildAiPrompt', () => {
  it('should include pre-extracted hints in the prompt', () => {
    const msg = 'PKR 1,500 spent at KFC';
    const hints = parseBankMessage(msg);
    const prompt = buildAiPrompt(msg, hints);

    expect(prompt).toContain('1,500');
    expect(prompt).toContain('bank message');
    expect(prompt).toContain('JSON');
  });

  it('should work even with no hints extracted', () => {
    const prompt = buildAiPrompt('Some message', { confidence: 0 });
    expect(prompt).toContain('bank message');
    expect(prompt).toContain('JSON');
  });

  it('should not reveal the keyword-guessed type to the AI', () => {
    // The AI's answer is cross-checked against these hints in resolveDirection, so
    // leaking the guess would let the model simply echo it, making a disagreement
    // impossible to detect.
    const msg = 'PKR 1,500 spent at KFC';
    const hints = parseBankMessage(msg);
    expect(hints.type).toBe('expense');

    const prompt = buildAiPrompt(msg, hints);
    expect(prompt).not.toContain('Transaction type');
    expect(prompt).not.toContain('Pre-extracted type');
  });

  it('should ask the AI for direction confidence and evidence', () => {
    const prompt = buildAiPrompt('PKR 1,500 spent at KFC', {});
    expect(prompt).toContain('typeConfidence');
    expect(prompt).toContain('directionEvidence');
  });
});

// ─── The merchant a bank message yields ───────────────────────────

describe('sanitizeBankMerchant', () => {
  const alfalah = bankSmsFixtures.cases.find((c) =>
    c.name.startsWith('Transfer to a person, sending bank named')
  );

  const hblPurchase =
    'HBL: Your Debit Card ending 1234 has been debited with PKR 1,500.00 at KFC on 15-01-24. Available Balance: PKR 50,000.00';

  it('keeps the person a transfer names', () => {
    // A real Pakistani SMS writes the two names with different prominence; the counterparty
    // is the one that belongs on the transaction.
    const result = sanitizeBankMerchant('HASSAN', alfalah.message);
    expect(result.merchant).toBe('HASSAN');
    expect(result.rejected).toBeNull();
  });

  it('drops the bank when it is spelled correctly', () => {
    expect(sanitizeBankMerchant('Alfalah Bank', alfalah.message).merchant).toBeNull();
    expect(sanitizeBankMerchant('Alfalah', alfalah.message).merchant).toBeNull();
  });

  it('drops a re-spelled name that appears nowhere in the message', () => {
    // The reported failure: the transaction was filed as "Alfaz bank".
    expect(sanitizeBankMerchant('Alfaz bank', alfalah.message).merchant).toBeNull();

    const result = sanitizeBankMerchant('Alfaz', alfalah.message);
    expect(result.merchant).toBeNull();
    expect(result.rejected).toMatch(/does not appear/);
  });

  it('drops a bank short code', () => {
    expect(sanitizeBankMerchant('HBL', hblPurchase).merchant).toBeNull();
  });

  it('drops the schema placeholder the parser falls back to', () => {
    expect(sanitizeBankMerchant('Unknown', alfalah.message).merchant).toBeNull();
  });

  it('keeps an ordinary merchant from a card purchase', () => {
    expect(sanitizeBankMerchant('KFC', hblPurchase).merchant).toBe('KFC');
  });

  it('keeps a legitimate expansion of a shop name', () => {
    // Word-by-word comparison, not whole-string, so filling in a shop's full name survives.
    const msg = 'POS purchase of PKR 850.00 made at METRO on card ending 4321.';
    expect(sanitizeBankMerchant('Metro Cash & Carry', msg).merchant).toBe(
      'Metro Cash & Carry'
    );
  });

  it('has nothing to check when no merchant was returned', () => {
    expect(sanitizeBankMerchant(undefined, 'anything')).toEqual({
      merchant: null,
      rejected: null,
    });
    expect(sanitizeBankMerchant('   ', 'anything')).toEqual({
      merchant: null,
      rejected: null,
    });
  });
});

describe('bank prompt merchant rules', () => {
  it('asks for the counterparty', () => {
    expect(BANK_MESSAGE_SYSTEM_PROMPT).toMatch(/counterparty/);
    expect(buildAiPrompt('PKR 100 transferred to ALI', {})).toMatch(/counterparty/);
  });

  it('rules the bank out explicitly', () => {
    expect(BANK_MESSAGE_SYSTEM_PROMPT).toMatch(
      /bank or wallet named in the message is never the merchant/
    );
  });

  it('requires names to be copied rather than corrected', () => {
    expect(BANK_MESSAGE_SYSTEM_PROMPT).toMatch(/Copy every name exactly/);
    expect(buildAiPrompt('PKR 100 transferred to ALI', {})).toMatch(
      /never invent one/
    );
  });
});
