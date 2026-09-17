const Tesseract = require('tesseract.js');
const { parseTextWithGroq, RECEIPT_SYSTEM_PROMPT } = require('./ai');

const ENABLE_TESSERACT = process.env.ENABLE_TESSERACT_FALLBACK !== 'false';

/**
 * Run Tesseract.js OCR on an image file to extract raw text.
 * @param {string} imagePath - Absolute path to the image file
 * @returns {Promise<string>} Raw OCR text
 */
async function runTesseractOcr(imagePath) {
  if (!ENABLE_TESSERACT) {
    throw new Error('Tesseract fallback is disabled (ENABLE_TESSERACT_FALLBACK=false)');
  }

  console.log(`[OCR] Running Tesseract.js on ${imagePath}`);
  const { data } = await Tesseract.recognize(imagePath, 'eng', {
    logger: (m) => {
      if (m.status === 'recognizing text' && m.progress % 0.25 === 0) {
        console.log(`[OCR] Progress: ${Math.round(m.progress * 100)}%`);
      }
    },
  });

  const text = (data.text || '').trim();
  if (!text) {
    throw new Error('Tesseract OCR returned empty text');
  }

  console.log(`[OCR] Extracted ${text.length} characters of text`);
  return text;
}

/**
 * Full fallback pipeline: Tesseract OCR → Groq Text API for structuring.
 * @param {string} imagePath - Absolute path to the image file
 * @returns {Promise<string>} Raw AI response text (JSON string)
 */
async function parseReceiptWithOcrFallback(imagePath) {
  // Step 1: OCR to get raw text
  const rawText = await runTesseractOcr(imagePath);

  // Step 2: Send raw text to Groq for structuring
  const userPrompt = `Extract the transaction details from the following OCR text of a receipt and return ONLY a valid JSON object.

OCR text:
${rawText}`;

  console.log('[OCR] Sending OCR text to Groq for structuring');
  return await parseTextWithGroq(RECEIPT_SYSTEM_PROMPT, userPrompt);
}

module.exports = {
  runTesseractOcr,
  parseReceiptWithOcrFallback,
};
