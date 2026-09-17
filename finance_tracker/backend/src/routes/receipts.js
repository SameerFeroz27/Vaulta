const express = require('express');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { db } = require('../config/db');
const { receipts, transactions } = require('../db/schema');
const { eq, and, desc, sql } = require('drizzle-orm');
const authenticate = require('../middleware/auth');
const { uploadReceipt } = require('../middleware/upload');
const { sendSuccess, sendError } = require('../utils/response');

const router = express.Router();

// All receipt routes require authentication
router.use(authenticate);

/**
 * POST /api/receipts/scan
 * Upload a receipt image (cash or virtual/online), create a queued receipt job.
 * Multipart form data: field "receipt" (image file) + optional "inputType" (image|virtual_receipt)
 */
router.post('/scan', uploadReceipt, async (req, res, next) => {
  try {
    const inputType = req.body.inputType === 'virtual_receipt' ? 'virtual_receipt' : 'image';

    // Optional user-selected transaction type (income/expense) for image receipts
    const transactionType =
      req.body.transactionType === 'income' ? 'income' : 'expense';

    // Compute SHA-256 file hash for deduplication
    const fileBuffer = fs.readFileSync(req.file.path);
    const fileHash = crypto.createHash('sha256').update(fileBuffer).digest('hex');

    // Check for duplicate receipt (same user + same file hash, already processed or processing)
    const [existing] = await db
      .select({
        id: receipts.id,
        status: receipts.status,
        transactionId: receipts.transactionId,
      })
      .from(receipts)
      .where(
        and(
          eq(receipts.userId, req.user.id),
          eq(receipts.fileHash, fileHash),
          sql`${receipts.status} IN ('success', 'processing', 'queued')`
        )
      )
      .limit(1);

    if (existing) {
      // Delete the newly uploaded file since it's a duplicate
      try { fs.unlinkSync(req.file.path); } catch {}

      // Mark the existing receipt's status as duplicate if it was successful
      if (existing.status === 'success') {
        await db
          .update(receipts)
          .set({ status: 'duplicate', updatedAt: new Date() })
          .where(eq(receipts.id, existing.id));
      }

      return sendSuccess(res, {
        receiptId: existing.id,
        status: 'duplicate',
        message: 'This receipt has already been uploaded',
        existingTransactionId: existing.transactionId,
      });
    }

    // Create the queued receipt job
    const [newReceipt] = await db
      .insert(receipts)
      .values({
        userId: req.user.id,
        inputType,
        filePath: req.file.path,
        fileHash,
        originalFileName: req.file.originalname,
        mimeType: req.file.mimetype,
        fileSizeBytes: req.file.size,
        rawPayload: { transactionType },
        status: 'queued',
      })
      .returning({
        id: receipts.id,
        status: receipts.status,
        inputType: receipts.inputType,
        createdAt: receipts.createdAt,
      });

    return sendSuccess(res, {
      receiptId: newReceipt.id,
      status: newReceipt.status,
      message: 'Receipt uploaded and queued for processing',
    }, 202);
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/receipts/bank-message
 * Submit a bank SMS/message for card transaction parsing.
 * Body: { message: string, source?: string }
 */
router.post('/bank-message', async (req, res, next) => {
  try {
    const { message } = req.body;

    if (!message || typeof message !== 'string' || message.trim().length === 0) {
      return sendError(res, 'Bank message text is required', 'VALIDATION_ERROR', 400);
    }

    if (message.length > 5000) {
      return sendError(res, 'Bank message cannot exceed 5000 characters', 'VALIDATION_ERROR', 400);
    }

    // Compute hash of the message text for dedup
    const textHash = crypto.createHash('sha256').update(message.trim()).digest('hex');

    // Check for duplicate
    const [existing] = await db
      .select({
        id: receipts.id,
        status: receipts.status,
        transactionId: receipts.transactionId,
      })
      .from(receipts)
      .where(
        and(
          eq(receipts.userId, req.user.id),
          eq(receipts.fileHash, textHash),
          sql`${receipts.status} IN ('success', 'processing', 'queued')`
        )
      )
      .limit(1);

    if (existing) {
      return sendSuccess(res, {
        receiptId: existing.id,
        status: 'duplicate',
        message: 'This bank message has already been processed',
        existingTransactionId: existing.transactionId,
      });
    }

    // Create the queued receipt job
    const [newReceipt] = await db
      .insert(receipts)
      .values({
        userId: req.user.id,
        inputType: 'bank_message',
        fileHash: textHash,
        rawText: message.trim(),
        status: 'queued',
      })
      .returning({
        id: receipts.id,
        status: receipts.status,
        inputType: receipts.inputType,
        createdAt: receipts.createdAt,
      });

    return sendSuccess(res, {
      receiptId: newReceipt.id,
      status: newReceipt.status,
      message: 'Bank message queued for processing',
    }, 202);
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/receipts/:id
 * Poll the status of a receipt job
 */
router.get('/:id', async (req, res, next) => {
  try {
    const receiptId = parseInt(req.params.id, 10);
    if (Number.isNaN(receiptId)) {
      return sendError(res, 'Invalid receipt ID', 'VALIDATION_ERROR', 400);
    }

    const [receipt] = await db
      .select({
        id: receipts.id,
        inputType: receipts.inputType,
        status: receipts.status,
        ocrProvider: receipts.ocrProvider,
        aiModel: receipts.aiModel,
        errorMessage: receipts.errorMessage,
        transactionId: receipts.transactionId,
        attempts: receipts.attempts,
        createdAt: receipts.createdAt,
        processedAt: receipts.processedAt,
      })
      .from(receipts)
      .where(and(eq(receipts.id, receiptId), eq(receipts.userId, req.user.id)))
      .limit(1);

    if (!receipt) {
      return sendError(res, 'Receipt not found', 'NOT_FOUND', 404);
    }

    // If linked to a transaction, include basic transaction info
    let transaction = null;
    if (receipt.transactionId) {
      const [tx] = await db
        .select({
          id: transactions.id,
          amount: transactions.amount,
          type: transactions.type,
          merchant: transactions.merchant,
          status: transactions.status,
          transactionDate: transactions.transactionDate,
        })
        .from(transactions)
        .where(eq(transactions.id, receipt.transactionId))
        .limit(1);
      transaction = tx || null;
    }

    return sendSuccess(res, { receipt, transaction });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/receipts
 * List all receipts for the authenticated user (paginated)
 */
router.get('/', async (req, res, next) => {
  try {
    const page = Math.max(parseInt(req.query.page, 10) || 1, 1);
    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 20, 1), 100);
    const offset = (page - 1) * limit;

    const rows = await db
      .select({
        id: receipts.id,
        inputType: receipts.inputType,
        status: receipts.status,
        ocrProvider: receipts.ocrProvider,
        transactionId: receipts.transactionId,
        createdAt: receipts.createdAt,
        processedAt: receipts.processedAt,
        amount: transactions.amount,
        merchant: transactions.merchant,
        transactionType: transactions.type,
      })
      .from(receipts)
      .leftJoin(transactions, eq(receipts.transactionId, transactions.id))
      .where(eq(receipts.userId, req.user.id))
      .orderBy(desc(receipts.createdAt))
      .limit(limit)
      .offset(offset);

    const [{ count: total }] = await db
      .select({ count: sql`count(*)::int` })
      .from(receipts)
      .where(eq(receipts.userId, req.user.id));

    return sendSuccess(res, {
      receipts: rows,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/receipts/:id/reprocess
 * Requeue a failed or needs_review receipt for processing
 */
router.post('/:id/reprocess', async (req, res, next) => {
  try {
    const receiptId = parseInt(req.params.id, 10);
    if (Number.isNaN(receiptId)) {
      return sendError(res, 'Invalid receipt ID', 'VALIDATION_ERROR', 400);
    }

    const [receipt] = await db
      .select({
        id: receipts.id,
        status: receipts.status,
        filePath: receipts.filePath,
      })
      .from(receipts)
      .where(and(eq(receipts.id, receiptId), eq(receipts.userId, req.user.id)))
      .limit(1);

    if (!receipt) {
      return sendError(res, 'Receipt not found', 'NOT_FOUND', 404);
    }

    if (receipt.status === 'queued' || receipt.status === 'processing') {
      return sendError(res, `Receipt is already ${receipt.status}`, 'INVALID_STATE', 400);
    }

    // Reset to queued for reprocessing
    await db
      .update(receipts)
      .set({
        status: 'queued',
        errorMessage: null,
        lockedAt: null,
        lockedBy: null,
        updatedAt: new Date(),
      })
      .where(eq(receipts.id, receiptId));

    return sendSuccess(res, {
      receiptId,
      status: 'queued',
      message: 'Receipt requeued for processing',
    });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
