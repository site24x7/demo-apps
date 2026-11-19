'use strict';
const { Pool } = require('pg');
const { config } = require('../config');
const logger = require('../logger');

let pool = null;
let isHealthy = false;
let lastError = null;
let retryTimer = null;
let retryCount = 0;

function createPool(customConfig) {
  const dbConfig = customConfig || config.db;
  const p = new Pool({
    host: dbConfig.host,
    port: dbConfig.port,
    database: dbConfig.database,
    user: dbConfig.user,
    password: dbConfig.password,
    max: dbConfig.max,
    connectionTimeoutMillis: dbConfig.connectionTimeoutMillis,
    idleTimeoutMillis: dbConfig.idleTimeoutMillis,
    statement_timeout: dbConfig.statementTimeoutMs,
  });

  p.on('error', (err) => {
    logger.error('Unexpected error on idle PostgreSQL client', { error: err.message });
  });

  return p;
}

function getPool() {
  if (!pool) {
    pool = createPool();
  }
  return pool;
}

function setPool(customPool) {
  pool = customPool;
  isHealthy = true;
  lastError = null;
}

async function checkConnection() {
  const p = getPool();
  try {
    const res = await p.query('SELECT 1 AS ok');
    if (res && res.rows) {
      if (!isHealthy) {
        logger.info('PostgreSQL connection established', {
          host: config.db.host,
          port: config.db.port,
          database: config.db.database,
        });
      }
      isHealthy = true;
      lastError = null;
      return true;
    }
  } catch (err) {
    isHealthy = false;
    lastError = err.message;
    return false;
  }
  return false;
}

function startConnectionRetry() {
  if (retryTimer) return;
  const retry = async () => {
    retryCount++;
    const ok = await checkConnection();
    if (ok) {
      retryTimer = null;
      retryCount = 0;
      return;
    }
    const delay = Math.min(
      config.db.startupRetryDelayMs * Math.pow(1.5, Math.min(retryCount, 8)),
      config.db.startupRetryMaxDelayMs
    );
    logger.warn('PostgreSQL connection attempt failed; retrying in background', {
      error: lastError,
      nextRetryMs: delay,
      attempt: retryCount,
    });
    retryTimer = setTimeout(retry, delay);
    if (retryTimer.unref) retryTimer.unref();
  };

  retry();
}

async function query(text, params) {
  const p = getPool();
  return p.query(text, params);
}

async function getClient() {
  const p = getPool();
  return p.connect();
}

async function checkHealth() {
  try {
    const ok = await checkConnection();
    return {
      status: ok ? 'UP' : 'DOWN',
      ...(lastError ? { error: lastError } : {}),
    };
  } catch (err) {
    return {
      status: 'DOWN',
      error: err.message,
    };
  }
}

async function close() {
  if (retryTimer) {
    clearTimeout(retryTimer);
    retryTimer = null;
  }
  if (pool) {
    try {
      await pool.end();
      logger.info('PostgreSQL pool closed');
    } catch (err) {
      logger.error('Error closing PostgreSQL pool', { error: err.message });
    }
  }
}

module.exports = {
  getPool,
  setPool,
  query,
  getClient,
  checkConnection,
  startConnectionRetry,
  checkHealth,
  close,
};
