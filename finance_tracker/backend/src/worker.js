require('dotenv').config();

const fs = require('fs');
const path = require('path');
const { db, pool } = require('./config/db');
const { receipts, transactions, sources, users } = require('./db/schema');
const { eq, and, inArray, sql } = require('drizzle-orm');

const { parseReceiptWithVision } = require('./services/ai');
const { parseTextWithGroq, RECEIPT_SYSTEM_PROMPT } = require('./services/ai');
const { parseReceiptWithOcrFallback } = require('./services/ocr');
const { parseBankMessage, buildAiPrompt } = require('./services/bank-message');
const { parseAndValidateAiOutput } = require('./validators/ai-output.schema');
const { findDuplicateByAmountAndDate } = require('./services/duplicate');

// ─── Configuration ───────────────────────────────────────────────
const POLL_INTERVAL_MS = 5000;
const STALE_LOCK_INTERVAL_MS = 60000;
const STALE_LOCK_THRESHOLD_MIN = 10;
const BATCH_SIZE = 5;
const WORKER_ID = `worker-${process.pid}`;

// ─── State ───────────────────────────────────────────────────────
let isShuttingDown = false;
let isProcessing = false;
let sourceMap = {};

// ─── Source ID cache ─────────────────────────────────────────────
async function loadSourceMap() {
  const rows = await db.select({ id: sources.id, name: sources.name }).from(sources);
  sourceMap = {};
  for (const row of rows) {
    sourceMap[row.name.toLowerCase()] = row.id;
  }
  console.log('[Worker] Source map loaded:', sourceMap);
}

function getSourceId(inputType) {
  switch (inputType) {
    case 'image':
      return sourceMap['cash'] || 2;
    case 'virtual_receipt':
      return sourceMap['online'] || 3;
    case 'bank_message':
      return sourceMap['card'] || 1;
    default:
      return sourceMap['cash'] || 2;
  }
}

// ─── Main polling loop ───────────────────────────────────────────
async function claimAndProcess() {
  if (isProcessing || isShuttingDown) return;
  isProcessing = true;

  try {
    // Claim queued receipts using FOR UPDATE SKIP LOCKED
    const claimedIds = await db.transaction(async (tx) => {
      const result = await tx.execute(sql`
        SELECT id FROM receipts
        WHERE status = 'queued'
        ORDER BY created_at ASC
        LIMIT ${BATCH_SIZE}
        FOR UPDATE SKIP LOCKED
      `);

      const ids = result.rows.map((r) => r.id);
      if (ids.length === 0) return [];

      await tx
        .update(receipts)
        .set({ status: 'processing', lockedAt: new Date(), lockedBy: WORKER_ID })
        .where(inArray(receipts.id, ids));

      return ids;
    });

    if (claimedIds.length === 0) return;

    console.log(`[Worker] Claimed ${claimedIds.length} receipt(s): ${claimedIds.join(', ')}`);

    // Process each receipt sequentially (to avoid overwhelming Groq API)
    for (const receiptId of claimedIds) {
      if (isShuttingDown) break;
      await processReceipt(receiptId);
    }
  } catch (err) {
    console.error('[Worker] Error in claimAndProcess:', err.message);
  } finally {
    isProcessing = false;
  }
}

// ─── Process a single receipt ────────────────────────────────────
async function processReceipt(receiptId) {
  let receipt;

  try {
    [receipt] = await db
      .select()
      .from(receipts)
      .where(eq(receipts.id, receiptId))
      .limit(1);

    if (!receipt) {
      console.warn(`[Worker] Receipt ${receiptId} not found, skipping`);
      return;
    }

    console.log(`[Worker] Processing receipt ${receiptId} (type: ${receipt.inputType})`);

    // Fetch the user's currency
    const [user] = await db
      .select({ currency: users.currency })
      .from(users)
      .where(eq(users.id, receipt.userId))
      .limit(1);

    // Step 1: Get raw AI response based on input type
    let rawAiResponse;
    let ocrProvider = 'none';
    let aiModel = process.env.GROQ_TEXT_MODEL || 'openai/gpt-oss-120b';

    if (receipt.inputType === 'image' || receipt.inputType === 'virtual_receipt') {
      // Image receipt — try Groq Vision, fall back to Tesseract + Groq Text
      const fullPath = path.isAbsolute(receipt.filePath)
        ? receipt.filePath
        : path.resolve(process.cwd(), receipt.filePath);

      if (!fs.existsSync(fullPath)) {
        throw new Error(`Image file not found: ${fullPath}`);
      }

      try {
        rawAiResponse = await parseReceiptWithVision(fullPath, receipt.mimeType || 'image/jpeg');
        ocrProvider = 'groq_vision';
        aiModel = process.env.GROQ_VISION_MODEL || 'qwen/qwen3.8-27b';
        console.log(`[Worker] Receipt ${receiptId}: Groq Vision succeeded`);
      } catch (visionErr) {
        console.warn(`[Worker] Receipt ${receiptId}: Groq Vision failed (${visionErr.message}), trying Tesseract fallback`);
        rawAiResponse = await parseReceiptWithOcrFallback(fullPath);
        ocrProvider = 'tesseract';
        console.log(`[Worker] Receipt ${receiptId}: Tesseract + Groq Text succeeded`);
      }
    } else if (receipt.inputType === 'bank_message') {
      // Bank message — pre-process with regex, then send to Groq Text
      const hints = parseBankMessage(receipt.rawText);
      const aiPrompt = buildAiPrompt(receipt.rawText, hints);

      const systemPrompt = `You are a bank transaction parser. Extract the transaction details from the bank message and return ONLY a valid JSON object with these fields:
- merchant: string (merchant or description)
- amount: number (transaction amount, positive)
- total: number (same as amount)
- date: string (YYYY-MM-DD format if available)
- type: string ("expense" for debit/spent, "income" for credit/received)
- cardLast4: string (last 4 digits of card if mentioned)
- bankReference: string (transaction reference number if available)
- description: string (additional details)
- confidence: number (0-1)

If a field is not present, omit it. Always return valid JSON.`;

      rawAiResponse = await parseTextWithGroq(systemPrompt, aiPrompt);
      ocrProvider = 'none';
      console.log(`[Worker] Receipt ${receiptId}: Groq Text succeeded (bank message)`);
    } else {
      throw new Error(`Unknown input type: ${receipt.inputType}`);
    }

    // Step 2: Parse and validate AI output
    const validationResult = parseAndValidateAiOutput(rawAiResponse);

    if (!validationResult.success) {
      // AI output couldn't be parsed — save raw response and mark for manual review
      console.warn(`[Worker] Receipt ${receiptId}: AI output validation failed: ${validationResult.error}`);
      await db
        .update(receipts)
        .set({
          status: 'needs_review',
          aiResponse: { raw: rawAiResponse, parseError: validationResult.error },
          ocrProvider,
          aiModel,
          processedAt: new Date(),
          updatedAt: new Date(),
        })
        .where(eq(receipts.id, receiptId));
      return;
    }

    const aiData = validationResult.data;

    // Step 3: Determine the transaction amount
    const amount = aiData.total || aiData.amount;
    if (!amount || amount <= 0) {
      throw new Error('AI output missing valid amount');
    }

    // Step 4: Determine transaction date
    let transactionDate = aiData.date || new Date().toISOString().slice(0, 10);
    // Normalize various date formats to YYYY-MM-DD
    if (!/^\d{4}-\d{2}-\d{2}$/.test(transactionDate)) {
      const parsed = new Date(transactionDate);
      if (!isNaN(parsed.getTime())) {
        transactionDate = parsed.toISOString().slice(0, 10);
      } else {
        transactionDate = new Date().toISOString().slice(0, 10);
      }
    }

    // Step 5: Check for duplicate transaction (same user + amount + date)
    const duplicateTx = await findDuplicateByAmountAndDate(receipt.userId, amount, transactionDate);

    if (duplicateTx) {
      console.log(`[Worker] Receipt ${receiptId}: Duplicate transaction found (id: ${duplicateTx.id})`);
      await db
        .update(receipts)
        .set({
          status: 'duplicate',
          aiResponse: aiData,
          ocrProvider,
          aiModel,
          transactionId: duplicateTx.id,
          processedAt: new Date(),
          updatedAt: new Date(),
        })
        .where(eq(receipts.id, receiptId));
      return;
    }

    // Step 6: Create the transaction (auto-confirmed; user can edit/delete later)
    const sourceId = getSourceId(receipt.inputType);

    // User-selected type takes priority over AI guess
    const userTransactionType = receipt.rawPayload?.transactionType;
    const transactionType = userTransactionType || aiData.type || 'expense';

    // Build description from items if available
    let description = aiData.description;
    if (!description && aiData.items && aiData.items.length > 0) {
      description = aiData.items.map((item) => `${item.quantity}x ${item.name}`).join(', ');
    }

    const [newTransaction] = await db
      .insert(transactions)
      .values({
        userId: receipt.userId,
        sourceId,
        amount: amount.toFixed(2),
        currency: aiData.currency || user?.currency || 'PKR',
        type: transactionType,
        status: 'confirmed',
        merchant: aiData.merchant || null,
        description: description || null,
        occurredAt: new Date(),
        transactionDate,
        cardLast4: aiData.cardLast4 || null,
        bankReference: aiData.bankReference || null,
        receiptId: receipt.id,
      })
      .returning({ id: transactions.id });

    // Step 7: Update receipt as success
    await db
      .update(receipts)
      .set({
        status: 'success',
        aiResponse: aiData,
        ocrProvider,
        aiModel,
        transactionId: newTransaction.id,
        processedAt: new Date(),
        updatedAt: new Date(),
      })
      .where(eq(receipts.id, receiptId));

    console.log(`[Worker] Receipt ${receiptId}: Success — transaction ${newTransaction.id} created (confirmed)`);
  } catch (err) {
    console.error(`[Worker] Receipt ${receiptId} failed:`, err.message);
    await handleReceiptFailure(receiptId, err);
  }
}

// ─── Handle receipt processing failure ───────────────────────────
async function handleReceiptFailure(receiptId, err) {
  try {
    const [receipt] = await db
      .select({ attempts: receipts.attempts, maxAttempts: receipts.maxAttempts })
      .from(receipts)
      .where(eq(receipts.id, receiptId))
      .limit(1);

    if (!receipt) return;

    const newAttempts = receipt.attempts + 1;

    if (newAttempts < receipt.maxAttempts) {
      // Retry — set back to queued
      await db
        .update(receipts)
        .set({
          status: 'queued',
          attempts: newAttempts,
          errorMessage: err.message,
          lockedAt: null,
          lockedBy: null,
          updatedAt: new Date(),
        })
        .where(eq(receipts.id, receiptId));
      console.log(`[Worker] Receipt ${receiptId}: Retrying (attempt ${newAttempts}/${receipt.maxAttempts})`);
    } else {
      // Max attempts reached — mark as failed
      await db
        .update(receipts)
        .set({
          status: 'failed',
          attempts: newAttempts,
          errorMessage: err.message,
          lockedAt: null,
          lockedBy: null,
          processedAt: new Date(),
          updatedAt: new Date(),
        })
        .where(eq(receipts.id, receiptId));
      console.log(`[Worker] Receipt ${receiptId}: Failed after ${newAttempts} attempts`);
    }
  } catch (updateErr) {
    console.error(`[Worker] Failed to update receipt ${receiptId} failure status:`, updateErr.message);
  }
}

// ─── Stale lock recovery ─────────────────────────────────────────
async function recoverStaleLocks() {
  if (isShuttingDown) return;

  try {
    const result = await db.execute(sql`
      UPDATE receipts
      SET status = 'queued', locked_at = NULL, locked_by = NULL, updated_at = now()
      WHERE status = 'processing'
        AND locked_at < now() - interval '${STALE_LOCK_THRESHOLD_MIN} minutes'
      RETURNING id
    `);

    if (result.rows.length > 0) {
      console.log(`[Worker] Recovered ${result.rows.length} stale locked receipt(s): ${result.rows.map((r) => r.id).join(', ')}`);
    }
  } catch (err) {
    console.error('[Worker] Stale lock recovery error:', err.message);
  }
}

// ─── Graceful shutdown ───────────────────────────────────────────
async function shutdown(signal) {
  console.log(`\n[${signal}] Worker shutting down gracefully...`);
  isShuttingDown = true;

  // Wait for current processing to finish
  while (isProcessing) {
    await new Promise((resolve) => setTimeout(resolve, 500));
  }

  try {
    await pool.end();
    console.log('[Worker] DB pool closed.');
  } catch (err) {
    console.error('[Worker] Error closing pool:', err.message);
  }

  process.exit(0);
}

// ─── Start worker ────────────────────────────────────────────────
async function start() {
  console.log(`[Worker] Starting (PID: ${process.pid}, ID: ${WORKER_ID})`);

  await loadSourceMap();

  const pollTimer = setInterval(claimAndProcess, POLL_INTERVAL_MS);
  const staleTimer = setInterval(recoverStaleLocks, STALE_LOCK_INTERVAL_MS);

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));

  console.log(`[Worker] Polling every ${POLL_INTERVAL_MS}ms, stale lock threshold: ${STALE_LOCK_THRESHOLD_MIN}min`);
}

start().catch((err) => {
  console.error('[Worker] Failed to start:', err);
  process.exit(1);
});
