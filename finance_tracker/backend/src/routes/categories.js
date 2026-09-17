const express = require('express');
const { db } = require('../config/db');
const { categories } = require('../db/schema');
const { eq, and, isNull, or } = require('drizzle-orm');
const authenticate = require('../middleware/auth');
const validate = require('../middleware/validate');
const { createCategorySchema, updateCategorySchema } = require('../validators/transaction.schema');
const { sendSuccess, sendError } = require('../utils/response');

const router = express.Router();

// All category routes require authentication
router.use(authenticate);

/**
 * GET /api/categories
 * Returns global default categories + user's custom categories
 */
router.get('/', async (req, res, next) => {
  try {
    const result = await db
      .select({
        id: categories.id,
        name: categories.name,
        icon: categories.icon,
        color: categories.color,
        transactionType: categories.transactionType,
        userId: categories.userId,
        isGlobal: isNull(categories.userId),
      })
      .from(categories)
      .where(
        or(
          isNull(categories.userId),
          eq(categories.userId, req.user.id)
        )
      )
      .orderBy(categories.name);

    return sendSuccess(res, { categories: result });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/categories
 * Create a custom category for the authenticated user
 */
router.post('/', validate(createCategorySchema), async (req, res, next) => {
  try {
    const { name, icon, color, transactionType } = req.body;

    // Check for duplicate name among user's categories + globals
    const existing = await db
      .select({ id: categories.id })
      .from(categories)
      .where(
        and(
          eq(categories.name, name),
          or(
            isNull(categories.userId),
            eq(categories.userId, req.user.id)
          )
        )
      )
      .limit(1);

    if (existing.length > 0) {
      return sendError(res, 'A category with this name already exists', 'CONFLICT', 409);
    }

    const [newCategory] = await db
      .insert(categories)
      .values({
        userId: req.user.id,
        name,
        icon,
        color,
        transactionType,
      })
      .returning({
        id: categories.id,
        name: categories.name,
        icon: categories.icon,
        color: categories.color,
        transactionType: categories.transactionType,
        userId: categories.userId,
        createdAt: categories.createdAt,
      });

    return sendSuccess(res, { category: newCategory }, 201);
  } catch (err) {
    next(err);
  }
});

/**
 * PUT /api/categories/:id
 * Update a user-owned category (cannot edit global categories)
 */
router.put('/:id', validate(updateCategorySchema), async (req, res, next) => {
  try {
    const categoryId = parseInt(req.params.id, 10);
    if (Number.isNaN(categoryId)) {
      return sendError(res, 'Invalid category ID', 'VALIDATION_ERROR', 400);
    }

    // Verify ownership — must be a user-created category, not a global one
    const [existing] = await db
      .select()
      .from(categories)
      .where(eq(categories.id, categoryId))
      .limit(1);

    if (!existing) {
      return sendError(res, 'Category not found', 'NOT_FOUND', 404);
    }

    if (existing.userId === null || existing.userId !== req.user.id) {
      return sendError(res, 'You can only edit your own custom categories', 'FORBIDDEN', 403);
    }

    const [updated] = await db
      .update(categories)
      .set({ ...req.body, updatedAt: new Date() })
      .where(eq(categories.id, categoryId))
      .returning({
        id: categories.id,
        name: categories.name,
        icon: categories.icon,
        color: categories.color,
        transactionType: categories.transactionType,
        userId: categories.userId,
        updatedAt: categories.updatedAt,
      });

    return sendSuccess(res, { category: updated });
  } catch (err) {
    next(err);
  }
});

/**
 * DELETE /api/categories/:id
 * Delete a user-owned category (cannot delete global categories)
 * Transactions referencing this category will have categoryId set to NULL
 */
router.delete('/:id', async (req, res, next) => {
  try {
    const categoryId = parseInt(req.params.id, 10);
    if (Number.isNaN(categoryId)) {
      return sendError(res, 'Invalid category ID', 'VALIDATION_ERROR', 400);
    }

    const [existing] = await db
      .select()
      .from(categories)
      .where(eq(categories.id, categoryId))
      .limit(1);

    if (!existing) {
      return sendError(res, 'Category not found', 'NOT_FOUND', 404);
    }

    if (existing.userId === null || existing.userId !== req.user.id) {
      return sendError(res, 'You can only delete your own custom categories', 'FORBIDDEN', 403);
    }

    await db.delete(categories).where(eq(categories.id, categoryId));

    return sendSuccess(res, { message: 'Category deleted successfully' });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
