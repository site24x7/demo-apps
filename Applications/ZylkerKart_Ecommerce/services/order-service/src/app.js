const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const compression = require('compression');

const cartRoutes = require('./routes/cart');
const orderRoutes = require('./routes/order');
const db = require('./config/db');
const redis = require('./config/redis');

const app = express();
const PORT = process.env.PORT || 8082;

// ─── Bootstrap ──────────────────────────────────────────────
// Async bootstrap ensures Chaos SDK middleware is registered
// BEFORE route handlers in the Express middleware stack.
(async () => {
  // ─── Base Middleware ────────────────────────────────────────
  app.use(cors());
  app.use(helmet());
  app.use(morgan('combined'));
  app.use(compression());
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true }));

  // ─── Site24x7 Labs Chaos SDK ──────────────────────────────
  // SDK is ESM, so we use dynamic import() from CJS.
  // Registering BEFORE routes ensures the middleware intercepts requests.
  try {
    const { initChaos } = await import('@site24x7-labs/chaos-sdk');
    initChaos(app, {
      appName: process.env.CHAOS_SDK_APP_NAME || 'order-service',
      configDir: process.env.CHAOS_SDK_CONFIG_DIR || '/var/site24x7-labs/faults',
      enabled: process.env.CHAOS_SDK_ENABLED !== 'false',
    });
  } catch (err) {
    console.warn('[chaos-sdk] Failed to initialize Chaos SDK:', err.message);
  }

  // ─── Routes ─────────────────────────────────────────────────
  app.use('/cart', cartRoutes);
  app.use('/orders', orderRoutes);

  // ─── Health Check ───────────────────────────────────────────
  app.get('/health', async (req, res) => {
    const health = {
      service: 'order-service',
      status: 'UP',
      timestamp: new Date().toISOString(),
      checks: {}
    };

    // Check MySQL
    try {
      const [rows] = await db.execute('SELECT 1 AS ok');
      health.checks.mysql = { status: 'UP' };
    } catch (err) {
      health.checks.mysql = { status: 'DOWN', error: err.message };
      health.status = 'DEGRADED';
    }

    // Check Redis
    try {
      const redisClient = redis.getRedis();
      await redisClient.ping();
      health.checks.redis = { status: 'UP' };
    } catch (err) {
      health.checks.redis = { status: 'DOWN', error: err.message };
      health.status = 'DEGRADED';
    }

    const statusCode = health.status === 'UP' ? 200 : 503;
    res.status(statusCode).json(health);
  });

  // ─── 404 Handler ────────────────────────────────────────────
  app.use((req, res) => {
    res.status(404).json({
      error: 'Not Found',
      message: `Route ${req.method} ${req.path} not found`,
      service: 'order-service'
    });
  });

  // ─── Global Error Handler ───────────────────────────────────
  app.use((err, req, res, next) => {
    console.error(`[ERROR] ${err.stack || err.message}`);
    res.status(err.status || 500).json({
      error: err.message || 'Internal Server Error',
      service: 'order-service',
      timestamp: new Date().toISOString()
    });
  });

  // ─── Start Server ───────────────────────────────────────────
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Order Service running on port ${PORT}`);
    console.log(`   MySQL: ${process.env.DB_HOST || 'mysql'}:${process.env.DB_PORT || 3306}/${process.env.DB_NAME || 'db_order'}`);
    console.log(`   Redis: ${process.env.REDIS_HOST || 'redis'}:${process.env.REDIS_PORT || 6379}`);
  });
})();

// ─── Graceful Shutdown ──────────────────────────────────────
process.on('SIGTERM', async () => {
  console.log('SIGTERM received. Shutting down gracefully...');
  try {
    await db.end();
    const redisClient = redis.getRedis();
    await redisClient.quit();
  } catch (err) {
    console.error('Error during shutdown:', err.message);
  }
  process.exit(0);
});

module.exports = app;
