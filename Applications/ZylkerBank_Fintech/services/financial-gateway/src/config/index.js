'use strict';

const int = (v, d) => {
  const n = parseInt(v, 10);
  return Number.isFinite(n) ? n : d;
};
const bool = (v, d) => (v === undefined || v === '' ? d : !['false', '0', 'no', 'off'].includes(String(v).toLowerCase()));

function loadConfig(env = process.env) {
  return {
    serviceName: 'financial-gateway',
    env: env.NODE_ENV || 'development',
    port: int(env.PORT, 8082),
    logLevel: (env.LOG_LEVEL || 'info').toLowerCase(),

    db: {
      host: env.DB_HOST || 'localhost',
      port: int(env.DB_PORT, 5432),
      database: env.DB_NAME || 'bank_db',
      user: env.DB_USER || 'postgres',
      password: env.DB_PASSWORD || 'ZylkerBank@2024',
      max: int(env.DB_POOL_MAX, 10),
      connectionTimeoutMillis: int(env.DB_CONNECT_TIMEOUT_MS, 3000),
      idleTimeoutMillis: 30000,
      statementTimeoutMs: int(env.DB_STATEMENT_TIMEOUT_MS, 15000),
      startupRetries: int(env.DB_STARTUP_RETRIES, 0), // 0 = retry forever (in background)
      startupRetryDelayMs: int(env.DB_STARTUP_RETRY_DELAY_MS, 2000),
      startupRetryMaxDelayMs: 15000,
    },

    kafka: {
      enabled: bool(env.KAFKA_ENABLED, true),
      brokers: (env.KAFKA_BROKERS || 'localhost:9092').split(',').map((s) => s.trim()).filter(Boolean),
      clientId: env.KAFKA_CLIENT_ID || 'financial-gateway',
      transfersTopic: env.KAFKA_TRANSFERS_TOPIC || 'bank.transfers.v1',
      cardsTopic: env.KAFKA_CARDS_TOPIC || 'bank.cards.v1',
      topicPartitions: int(env.KAFKA_TOPIC_PARTITIONS, 3),
      replicationFactor: int(env.KAFKA_REPLICATION_FACTOR, 1),
      connectionTimeoutMs: int(env.KAFKA_CONNECTION_TIMEOUT_MS, 3000),
      publishTimeoutMs: int(env.KAFKA_PUBLISH_TIMEOUT_MS, 3000),
      reconnectMaxDelayMs: 30000,
      bufferMax: int(env.KAFKA_BUFFER_MAX, 1000),
    },

    ledgerUrl: (env.LEDGER_URL || 'http://localhost:8081').replace(/\/+$/, ''),
    riskUrl: (env.RISK_URL || 'http://localhost:8083').replace(/\/+$/, ''),
    internalToken: env.INTERNAL_TOKEN || 'zylkerbank-internal-dev-token',
    ledgerTimeoutMs: int(env.LEDGER_TIMEOUT_MS, 10000),
    riskTimeoutMs: int(env.RISK_TIMEOUT_MS, 2000),

    jwtSecret: env.JWT_SECRET || 'zylkerbank-dev-jwt-secret-please-change-0123456789',
    cardEncryptionKey: env.CARD_ENCRYPTION_KEY || 'zylkerbank-card-encryption-dev-key-change-me',
    cardEncryptionKeyIsDefault: !env.CARD_ENCRYPTION_KEY,

    maxCardsPerUser: int(env.MAX_CARDS_PER_USER, 5),
    cardDefaultSpendingLimit: '1000.00',
    cardMaxSpendingLimit: 100000,
    cardValidityYears: 3,
    cardsAccountPool: env.CARD_POOL_ACCOUNT || '2170000999',

    idempotencyStaleSeconds: int(env.IDEMPOTENCY_STALE_SECONDS, 120),

    chaos: {
      enabled: bool(env.CHAOS_SDK_ENABLED, env.NODE_ENV !== 'test'),
      appName: env.CHAOS_SDK_APP_NAME || 'financial-gateway',
      configDir: env.CHAOS_SDK_CONFIG_DIR || '/var/site24x7-labs/faults',
    },
    otelDisabled: String(env.OTEL_SDK_DISABLED).toLowerCase() === 'true',
    shutdownTimeoutMs: int(env.SHUTDOWN_TIMEOUT_MS, 10000),
  };
}

module.exports = { loadConfig, config: loadConfig() };
