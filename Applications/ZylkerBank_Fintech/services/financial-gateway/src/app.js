'use strict';
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');

const { config } = require('./config');
const logger = require('./logger');
const db = require('./db/pool');
const kafkaProducer = require('./kafka/producer');

const correlationIdMiddleware = require('./middleware/correlationId');
const authenticate = require('./middleware/auth');
const errorHandler = require('./middleware/errorHandler');

const healthRoutes = require('./routes/health');
const transfersRoutes = require('./routes/transfers');
const cardsRoutes = require('./routes/cards');

const app = express();
let server = null;

// Base middlewares
app.use(cors());
app.use(helmet());
app.use(compression());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(correlationIdMiddleware);

const appReady = (async () => {
  // Site24x7 Labs Chaos SDK
  if (config.chaos.enabled) {
    try {
      const { initChaos } = await import('site24x7-chaos-sdk');
      const chaosEngine = initChaos(app, {
        appName: config.chaos.appName,
        configDir: config.chaos.configDir,
        enabled: config.chaos.enabled,
      });
      app.chaosEngine = chaosEngine;

      if (chaosEngine?.resourceFaultInjector?.registerDb) {
        chaosEngine.resourceFaultInjector.registerDb(db.getPool());
      }
      logger.info('Site24x7 Chaos SDK initialized', { appName: config.chaos.appName });
    } catch (err) {
      logger.warn('Failed to initialize Chaos SDK (non-fatal)', { error: err.message });
    }
  }

  // Health endpoint (public)
  app.use('/health', healthRoutes);
  app.use('/api/v1/health', healthRoutes);

  // Authenticated API v1 routes
  app.use('/api/v1', authenticate);
  app.use('/api/v1/transfers', transfersRoutes);
  app.use('/api/v1/cards', cardsRoutes);

  // 404 handler
  app.use((req, res) => {
    res.status(404).json({
      error: 'NOT_FOUND',
      message: `Route ${req.method} ${req.path} not found`,
      service: config.serviceName,
    });
  });

  // Global error handler
  app.use(errorHandler);

  return app;
})();

app.appReady = appReady;

async function startServer() {
  await appReady;

  // Background startup tasks (retry if dependencies absent)
  db.startConnectionRetry();
  kafkaProducer.connectProducer().catch(() => {});

  return new Promise((resolve) => {
    server = app.listen(config.port, '0.0.0.0', () => {
      logger.info(`Financial Gateway listening on port ${config.port}`, {
        port: config.port,
        env: config.env,
        dbHost: config.db.host,
        dbPort: config.db.port,
        dbName: config.db.database,
        kafkaBrokers: config.kafka.brokers,
      });
      resolve(server);
    });
  });
}

async function shutdown(signal) {
  logger.info(`Received ${signal}, initiating graceful shutdown...`, { signal });

  const forceExit = setTimeout(() => {
    logger.error('Shutdown timed out, forcing exit');
    process.exit(1);
  }, config.shutdownTimeoutMs);
  if (forceExit.unref) forceExit.unref();

  try {
    if (server) {
      await new Promise((resolve) => server.close(resolve));
      logger.info('HTTP server closed');
    }
    await db.close();
    await kafkaProducer.close();
    if (typeof global.__otelShutdown === 'function') {
      await global.__otelShutdown();
    }
    logger.info('Graceful shutdown completed');
    process.exit(0);
  } catch (err) {
    logger.error('Error during shutdown', { error: err.message });
    process.exit(1);
  }
}

if (require.main === module) {
  startServer().catch((err) => {
    logger.error('Failed to start server', { error: err.message, stack: err.stack });
    process.exit(1);
  });

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

module.exports = app;
module.exports.app = app;
module.exports.appReady = appReady;
module.exports.startServer = startServer;
module.exports.shutdown = shutdown;
