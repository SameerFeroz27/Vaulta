const { db, pool } = require('../config/db');
const { sources, categories } = require('./schema');
const { eq, isNull, and } = require('drizzle-orm');

async function seed() {
  console.log('--- Starting Database Seed ---');

  // 1. Seed default sources (Card, Cash, Online)
  const defaultSources = [
    { id: 1, name: 'Card' },
    { id: 2, name: 'Cash' },
    { id: 3, name: 'Online' },
  ];

  for (const src of defaultSources) {
    const existing = await db.select().from(sources).where(eq(sources.name, src.name)).limit(1);
    if (existing.length === 0) {
      await db.insert(sources).values(src);
      console.log(`[Seed] Inserted source: ${src.name}`);
    }
  }

  // 2. Seed default global categories (userId = null)
  const defaultCategories = [
    { name: 'Food & Dining', icon: '🍽️', color: '#FF6B6B', transactionType: 'expense' },
    { name: 'Transport', icon: '🚗', color: '#4ECDC4', transactionType: 'expense' },
    { name: 'Shopping', icon: '🛍️', color: '#45B7D1', transactionType: 'expense' },
    { name: 'Bills & Utilities', icon: '💡', color: '#96CEB4', transactionType: 'expense' },
    { name: 'Entertainment', icon: '🎬', color: '#FFEAA7', transactionType: 'expense' },
    { name: 'Health', icon: '🏥', color: '#DDA0DD', transactionType: 'expense' },
    { name: 'Education', icon: '📚', color: '#98D8C8', transactionType: 'expense' },
    { name: 'Salary', icon: '💰', color: '#2ECC71', transactionType: 'income' },
    { name: 'Freelance', icon: '💻', color: '#3498DB', transactionType: 'income' },
    { name: 'Other', icon: '📁', color: '#BDC3C7', transactionType: 'both' },
  ];

  for (const cat of defaultCategories) {
    const existing = await db
      .select()
      .from(categories)
      .where(and(eq(categories.name, cat.name), isNull(categories.userId)))
      .limit(1);

    if (existing.length === 0) {
      await db.insert(categories).values({
        userId: null,
        name: cat.name,
        icon: cat.icon,
        color: cat.color,
        transactionType: cat.transactionType,
      });
      console.log(`[Seed] Inserted category: ${cat.name}`);
    }
  }

  console.log('--- Database Seed Complete ---');
}

if (require.main === module) {
  seed()
    .then(() => pool.end())
    .catch((err) => {
      console.error('Seed failed:', err);
      pool.end();
      process.exit(1);
    });
}

module.exports = { seed };
