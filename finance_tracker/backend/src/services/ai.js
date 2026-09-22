const fs = require('fs');
const path = require('path');
const { Groq } = require('groq-sdk');

const groq = new Groq({ apiKey: process.env.GROQ_API_KEY });

const VISION_MODEL = process.env.GROQ_VISION_MODEL || 'qwen/qwen3.8-27b';
const TEXT_MODEL = process.env.GROQ_TEXT_MODEL || 'openai/gpt-oss-120b';
const ENABLE_GROQ_VISION = process.env.ENABLE_GROQ_VISION !== 'false';

const MAX_RETRIES = 3;
const RATE_LIMIT_BACKOFF_MS = 5000;

/**
 * Strip <think>...</think> reasoning tags that reasoning models
 * (e.g. Qwen, GPT-OSS) embed in the content before the actual JSON.
 */
function stripReasoningTags(text) {
  if (!text || typeof text !== 'string') return text;
  return text.replace(/<think>[\s\S]*?<\/think>/gi, '').trim();
}

// ─── Prompts ─────────────────────────────────────────────────────

const RECEIPT_SYSTEM_PROMPT = `You are a receipt parsing assistant. Extract all transaction details from the receipt image and return ONLY a valid JSON object with these fields:
- merchant: string (store/merchant name)
- amount: number (total amount paid)
- total: number (same as amount)
- subtotal: number (amount before tax, if shown)
- tax: number (tax amount, if shown)
- date: string (transaction date in YYYY-MM-DD format)
- time: string (transaction time if visible)
- currency: string (3-letter currency code, e.g. PKR, USD)
- type: string ("expense" for purchases/payments made, "income" for refunds/payments received)
- paymentMethod: string (cash, card, etc. if visible)
- cardLast4: string (last 4 digits of card if visible)
- items: array of objects with { name: string, quantity: number, price: number }
- confidence: number (0-1, your confidence in the extraction)

If a field is not present in the receipt, omit it. Always return valid JSON.`;

/**
 * Call Groq Vision API to parse a receipt image.
 * @param {string} imagePath - Absolute path to the image file
 * @param {string} mimeType - MIME type of the image
 * @returns {Promise<string>} Raw AI response text (JSON string)
 */
async function parseReceiptWithVision(imagePath, mimeType) {
  if (!ENABLE_GROQ_VISION) {
    throw new Error('Groq Vision is disabled (ENABLE_GROQ_VISION=false)');
  }

  const imageBuffer = fs.readFileSync(imagePath);
  const base64Image = imageBuffer.toString('base64');
  const dataUrl = `data:${mimeType};base64,${base64Image}`;

  return await callGroqWithRetry(async (useJsonFormat) => {
    const response = await groq.chat.completions.create({
      model: VISION_MODEL,
      messages: [
        {
          role: 'user',
          content: [
            { type: 'text', text: RECEIPT_SYSTEM_PROMPT },
            { type: 'image_url', image_url: { url: dataUrl } },
          ],
        },
      ],
      temperature: 0,
      max_tokens: 8192,
      ...(useJsonFormat ? { response_format: { type: 'json_object' } } : {}),
    });
    return stripReasoningTags(response.choices[0].message.content);
  });
}

/**
 * Call Groq Text API to parse raw text (OCR output or bank message).
 * @param {string} systemPrompt - System prompt describing the task
 * @param {string} userPrompt - User prompt with the text to parse
 * @returns {Promise<string>} Raw AI response text (JSON string)
 */
async function parseTextWithGroq(systemPrompt, userPrompt) {
  return await callGroqWithRetry(async (useJsonFormat) => {
    const response = await groq.chat.completions.create({
      model: TEXT_MODEL,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt },
      ],
      temperature: 0,
      max_tokens: 8192,
      ...(useJsonFormat ? { response_format: { type: 'json_object' } } : {}),
    });
    return stripReasoningTags(response.choices[0].message.content);
  });
}

/**
 * Call Groq with retry logic for rate limits (429) and response_format errors.
 * Tries with JSON format first, then falls back to no format on error.
 */
async function callGroqWithRetry(fn) {
  let lastError;

  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    // Try with JSON format on first attempt, without on retry if it failed
    const useJsonFormat = attempt === 0;

    try {
      return await fn(useJsonFormat);
    } catch (err) {
      lastError = err;

      // Rate limit — back off and retry
      if (err.status === 429 || err.error?.status === 429) {
        const waitMs = RATE_LIMIT_BACKOFF_MS * (attempt + 1);
        console.warn(`[AI] Rate limited (429), backing off ${waitMs}ms (attempt ${attempt + 1}/${MAX_RETRIES})`);
        await sleep(waitMs);
        continue;
      }

      // response_format not supported — retry without it
      if (attempt === 0 && useJsonFormat) {
        console.warn('[AI] Retrying without response_format (model may not support JSON mode)');
        continue;
      }

      // Other error — retry with backoff
      if (attempt < MAX_RETRIES - 1) {
        const waitMs = RATE_LIMIT_BACKOFF_MS * (attempt + 1);
        console.warn(`[AI] Error: ${err.message}, retrying in ${waitMs}ms (attempt ${attempt + 1}/${MAX_RETRIES})`);
        await sleep(waitMs);
        continue;
      }
    }
  }

  throw lastError || new Error('AI call failed after all retries');
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

module.exports = {
  parseReceiptWithVision,
  parseTextWithGroq,
  RECEIPT_SYSTEM_PROMPT,
};
