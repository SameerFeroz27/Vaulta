require('dotenv').config();
const { fork } = require('child_process');
const path = require('path');
const app = require('./app');
const { pool } = require('./config/db');
const { cleanupExpiredTokens } = require('./utils/token-cleanup');
const { runMigrations } = require('./db/run-migrations');
const { seed } = require('./db/seed');

const PORT = process.env.PORT || 5000;
const AUTO_MIGRATE = process.env.AUTO_MIGRATE !== 'false';
const AUTO_SEED = process.env.AUTO_SEED !== 'false';

async function boot() {
  // 1. Verify PostgreSQL is reachable before doing anything else.
  console.log('[DB] Checking connection...');
  try {
    await pool.query('SELECT 1');
    console.log('[DB] Connection verified.');
  } catch (err) {
    console.error('[DB] Cannot connect to PostgreSQL.');
    console.error(`[DB] DATABASE_URL: ${process.env.DATABASE_URL}`);
    console.error('[DB] Make sure PostgreSQL is installed and running.');
    console.error('[DB] On Windows: start the "postgresql" service from Services.msc or run "pg_ctl start".');
    process.exit(1);
  }

  // 2. Apply pending migrations.
  if (AUTO_MIGRATE) {
    console.log('[DB] Running migrations...');
    try {
      await runMigrations();
      console.log('[DB] Migrations complete.');
    } catch (err) {
      console.error('[DB] Migration failed:', err.message);
      process.exit(1);
    }
  }

  // 3. Seed default data (idempotent — safe on every boot).
  if (AUTO_SEED) {
    console.log('[DB] Running seed...');
    try {
      await seed();
      console.log('[DB] Seed complete.');
    } catch (err) {
      console.error('[DB] Seed failed:', err.message);
      process.exit(1);
    }
  }

  // 4. Start the Express server.
  const server = app.listen(PORT, () => {
    console.log(`🚀 Finance Tracker API Server running on port ${PORT}`);
    console.log(`📍 Health check available at: http://localhost:${PORT}/api/health`);
  });

  // 5. Start the receipt-processing worker as a child process so queued
  //    receipts are processed automatically without a separate terminal.
  const ENABLE_WORKER = process.env.ENABLE_WORKER !== 'false';
  let workerProcess = null;

  if (ENABLE_WORKER) {
    workerProcess = fork(path.join(__dirname, 'worker.js'), [], {
      stdio: 'inherit',
    });

    workerProcess.on('exit', (code) => {
      console.warn(`[Server] Worker exited (code ${code}). Restarting in 3s...`);
      setTimeout(() => {
        workerProcess = fork(path.join(__dirname, 'worker.js'), [], {
          stdio: 'inherit',
        });
      }, 3000);
    });

    console.log(`[Server] Receipt worker started (PID: ${workerProcess.pid})`);
  }

  // 6. Periodic refresh token cleanup (every 1 hour)
  const CLEANUP_INTERVAL_MS = 60 * 60 * 1000;
  const cleanupTimer = setInterval(cleanupExpiredTokens, CLEANUP_INTERVAL_MS);
  cleanupTimer.unref();

  // 7. Graceful shutdown
  async function shutdown(signal) {
    console.log(`\n[${signal}] Shutting down gracefully...`);
    clearInterval(cleanupTimer);

    if (workerProcess) {
      workerProcess.kill('SIGTERM');
      console.log('[Server] Worker shutdown signal sent.');
    }

    server.close(() => {
      console.log('[Server] HTTP server closed.');
    });
    try {
      await pool.end();
      console.log('[DB] Connection pool closed.');
    } catch (err) {
      console.error('[DB] Error closing pool:', err.message);
    }
    process.exit(0);
  }

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

// Catch uncaught errors to prevent silent crashes
process.on('uncaughtException', (err) => {
  console.error('[Uncaught Exception]', err);
});

process.on('unhandledRejection', (reason) => {
  console.error('[Unhandled Rejection]', reason);
});

boot();
