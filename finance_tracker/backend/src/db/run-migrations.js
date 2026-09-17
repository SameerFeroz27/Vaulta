const path = require('path');
const { migrate } = require('drizzle-orm/node-postgres/migrator');
const { db } = require('../config/db');

/**
 * Apply pending Drizzle migrations programmatically.
 * Uses the same __drizzle_migrations tracking table as `drizzle-kit migrate`,
 * so this is fully compatible with the CLI.
 */
async function runMigrations() {
  const migrationsFolder = path.join(__dirname, 'migrations');
  await migrate(db, { migrationsFolder });
}

module.exports = { runMigrations };
