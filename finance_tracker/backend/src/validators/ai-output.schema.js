const { z } = require('zod');

/**
 * Zod schema for AI-extracted transaction data.
 * Covers both receipt OCR results and bank message parsing.
 */
const aiTransactionSchema = z.object({
  merchant: z.string().optional().default('Unknown'),
  amount: z.number().nonnegative().optional(),
  total: z.number().nonnegative().optional(),
  subtotal: z.number().nonnegative().optional(),
  tax: z.number().nonnegative().optional(),
  date: z.string().optional(),
  time: z.string().optional(),
  currency: z.string().length(3).optional(),
  type: z.enum(['expense', 'income']).optional().default('expense'),
  paymentMethod: z.string().optional(),
  cardLast4: z.string().length(4).optional(),
  bankReference: z.string().optional(),
  description: z.string().optional(),
  items: z.array(
    z.object({
      name: z.string(),
      quantity: z.number().positive().optional().default(1),
      price: z.number().nonnegative(),
    })
  ).optional(),
  confidence: z.number().min(0).max(1).optional(),
});

/**
 * Strip markdown code fences from a string.
 * Handles ```json ... ```, ``` ... ```, and plain JSON.
 */
function stripMarkdownFences(text) {
  if (!text || typeof text !== 'string') return text;

  let cleaned = text.trim();

  // Remove opening fence: ```json, ```JSON, ```
  cleaned = cleaned.replace(/^```(?:json|JSON)?\s*\n?/, '');

  // Remove closing fence: ```
  cleaned = cleaned.replace(/\n?```\s*$/, '');

  return cleaned.trim();
}

/**
 * Safely parse a JSON string that may be wrapped in markdown fences
 * or contain extra prose around the JSON object.
 * Returns { success, data, error }.
 */
function safeJsonParse(rawText) {
  if (!rawText || typeof rawText !== 'string') {
    return { success: false, error: 'Empty or non-string input' };
  }

  // Step 1: strip markdown fences
  let cleaned = stripMarkdownFences(rawText);

  // Step 2: try direct parse
  try {
    return { success: true, data: JSON.parse(cleaned) };
  } catch {
    // continue to fallback
  }

  // Step 3: try to extract the first { ... } block
  const jsonMatch = cleaned.match(/\{[\s\S]*\}/);
  if (jsonMatch) {
    try {
      return { success: true, data: JSON.parse(jsonMatch[0]) };
    } catch {
      // continue
    }
  }

  // Step 4: try to extract the first [ ... ] array
  const arrayMatch = cleaned.match(/\[[\s\S]*\]/);
  if (arrayMatch) {
    try {
      return { success: true, data: JSON.parse(arrayMatch[0]) };
    } catch {
      // continue
    }
  }

  return { success: false, error: 'Could not parse JSON from AI response' };
}

/**
 * Full pipeline: raw AI text → stripped → parsed → Zod validated.
 * Returns { success, data, error }.
 */
function parseAndValidateAiOutput(rawText) {
  const parsed = safeJsonParse(rawText);
  if (!parsed.success) {
    return { success: false, error: parsed.error, rawText };
  }

  const result = aiTransactionSchema.safeParse(parsed.data);
  if (!result.success) {
    return {
      success: false,
      error: `Validation failed: ${result.error.errors.map((e) => `${e.path.join('.')}: ${e.message}`).join(', ')}`,
      rawText,
      rawData: parsed.data,
    };
  }

  return { success: true, data: result.data };
}

module.exports = {
  aiTransactionSchema,
  stripMarkdownFences,
  safeJsonParse,
  parseAndValidateAiOutput,
};
