'use strict';
const crypto = require('crypto');
const { Kafka, Partitioners } = require('kafkajs');
const { config } = require('../config');
const logger = require('../logger');

process.env.KAFKAJS_NO_PARTITIONER_WARNING = '1';

let kafka = null;
let producer = null;
let isConnected = false;
let isConnecting = false;
let lastError = null;

function initKafka() {
  if (!config.kafka.enabled) {
    logger.info('Kafka is disabled by configuration');
    return null;
  }
  if (!kafka) {
    kafka = new Kafka({
      clientId: config.kafka.clientId,
      brokers: config.kafka.brokers,
      connectionTimeout: config.kafka.connectionTimeoutMs,
    });
  }
  return kafka;
}

function getProducer() {
  if (!config.kafka.enabled) return null;
  if (!producer) {
    const k = initKafka();
    if (!k) return null;
    producer = k.producer({
      idempotent: true,
      createPartitioner: Partitioners.DefaultPartitioner,
      maxInFlightRequests: 1,
    });

    producer.on(producer.events.CONNECT, () => {
      isConnected = true;
      lastError = null;
      logger.info('Kafka producer connected', { brokers: config.kafka.brokers });
    });

    producer.on(producer.events.DISCONNECT, () => {
      isConnected = false;
      logger.warn('Kafka producer disconnected');
    });
  }
  return producer;
}

async function connectProducer() {
  if (!config.kafka.enabled || isConnected || isConnecting) return;
  isConnecting = true;
  try {
    const p = getProducer();
    if (p) {
      await p.connect();
      isConnected = true;
      lastError = null;
    }
  } catch (err) {
    isConnected = false;
    lastError = err.message;
    logger.warn('Kafka producer failed to connect on startup (will retry on demand)', {
      error: err.message,
      brokers: config.kafka.brokers,
    });
  } finally {
    isConnecting = false;
  }
}

/**
 * Best-effort publish: Kafka failure must NEVER fail the API call.
 */
async function sendEvent({ topic, key, eventType, data, correlationId }) {
  if (!config.kafka.enabled) {
    logger.debug('Kafka disabled, skipping event publish', { eventType, topic });
    return null;
  }

  const envelope = {
    event_id: crypto.randomUUID(),
    event_type: eventType,
    correlation_id: correlationId || logger.getCorrelationId() || crypto.randomUUID(),
    occurred_at: new Date().toISOString(),
    data: data || {},
  };

  try {
    const p = getProducer();
    if (!p) return null;

    if (!isConnected) {
      // Lazy attempt to connect
      await connectProducer();
    }

    if (!isConnected) {
      logger.warn('Kafka not connected; dropping event (best-effort)', {
        eventType,
        topic,
        eventId: envelope.event_id,
      });
      return null;
    }

    await p.send({
      topic,
      messages: [
        {
          key: key ? String(key) : undefined,
          value: JSON.stringify(envelope),
        },
      ],
      timeout: config.kafka.publishTimeoutMs,
    });

    logger.debug('Kafka event published', {
      topic,
      eventType,
      eventId: envelope.event_id,
      key,
    });
    return envelope;
  } catch (err) {
    lastError = err.message;
    logger.warn('Failed to publish Kafka event (best-effort, ignoring)', {
      error: err.message,
      topic,
      eventType,
      eventId: envelope.event_id,
    });
    return null;
  }
}

async function checkHealth() {
  if (!config.kafka.enabled) {
    return { status: 'DISABLED' };
  }
  return {
    status: isConnected ? 'UP' : 'DOWN',
    ...(lastError ? { error: lastError } : {}),
  };
}

async function close() {
  if (producer && isConnected) {
    try {
      await producer.disconnect();
      isConnected = false;
      logger.info('Kafka producer disconnected');
    } catch (err) {
      logger.error('Error disconnecting Kafka producer', { error: err.message });
    }
  }
}

module.exports = {
  getProducer,
  connectProducer,
  sendEvent,
  checkHealth,
  close,
};
