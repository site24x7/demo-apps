'use strict';
const crypto = require('crypto');
const db = require('../db/pool');
const { conflict, unprocessable } = require('../errors');
const logger = require('../logger');

function computeHash(accountNumber, body) {
  const sorted = {};
  if (body && typeof body === 'object') {
    Object.keys(body).sort().forEach((k) => {
      sorted[k] = body[k];
    });
  }
  const raw = `${accountNumber}:${JSON.stringify(sorted)}`;
  return crypto.createHash('sha256').update(raw, 'utf8').digest('hex');
}

async function claim(idempotencyKey, requestHash, staleSeconds = 120) {
  // Try atomic insert
  const insertSql = `
    INSERT INTO idempotency_keys (idempotency_key, request_hash, status, created_at)
    VALUES ($1, $2, 'IN_PROGRESS', CURRENT_TIMESTAMP)
    ON CONFLICT (idempotency_key) DO NOTHING
    RETURNING *;
  `;

  const insertRes = await db.query(insertSql, [idempotencyKey, requestHash]);
  if (insertRes.rows.length > 0) {
    return { claimed: true };
  }

  // Row already exists, inspect state
  const selectSql = `SELECT * FROM idempotency_keys WHERE idempotency_key = $1;`;
  const selectRes = await db.query(selectSql, [idempotencyKey]);

  if (selectRes.rows.length === 0) {
    // Highly unlikely race where row was deleted right after conflict, retry insert
    return claim(idempotencyKey, requestHash, staleSeconds);
  }

  const existing = selectRes.rows[0];

  // Check request hash
  if (existing.request_hash !== requestHash) {
    throw unprocessable('IDEMPOTENCY_KEY_REUSED', 'Idempotency key was previously used with a different request payload');
  }

  // Completed request replay
  if (existing.status === 'COMPLETED') {
    return {
      claimed: false,
      replayed: true,
      status: existing.response_status || 200,
      payload: existing.response_payload,
    };
  }

  // In progress
  if (existing.status === 'IN_PROGRESS') {
    const createdAtMs = new Date(existing.created_at).getTime();
    const ageSeconds = (Date.now() - createdAtMs) / 1000;

    if (ageSeconds > staleSeconds) {
      logger.warn('Recovering stale IN_PROGRESS idempotency key', {
        idempotencyKey,
        ageSeconds,
        staleSeconds,
      });

      const updateSql = `
        UPDATE idempotency_keys
        SET status = 'IN_PROGRESS', created_at = CURRENT_TIMESTAMP
        WHERE idempotency_key = $1 AND status = 'IN_PROGRESS'
        RETURNING *;
      `;
      const updateRes = await db.query(updateSql, [idempotencyKey]);
      if (updateRes.rows.length > 0) {
        return { claimed: true, staleRecovered: true };
      }
    }

    throw conflict('IDEMPOTENCY_IN_PROGRESS', 'A request with this idempotency key is currently being processed');
  }

  // Failed state can be retried
  if (existing.status === 'FAILED') {
    logger.info('Retrying previously FAILED idempotency key', { idempotencyKey });
    const updateSql = `
      UPDATE idempotency_keys
      SET status = 'IN_PROGRESS', created_at = CURRENT_TIMESTAMP
      WHERE idempotency_key = $1 AND status = 'FAILED'
      RETURNING *;
    `;
    const updateRes = await db.query(updateSql, [idempotencyKey]);
    if (updateRes.rows.length > 0) {
      return { claimed: true, retryingFailed: true };
    }
    throw conflict('IDEMPOTENCY_IN_PROGRESS', 'A request with this idempotency key is currently being processed');
  }

  throw conflict('IDEMPOTENCY_IN_PROGRESS', 'A request with this idempotency key is currently being processed');
}

async function complete(idempotencyKey, responseStatus, responsePayload) {
  const sql = `
    UPDATE idempotency_keys
    SET status = 'COMPLETED',
        response_status = $2,
        response_payload = $3,
        completed_at = CURRENT_TIMESTAMP
    WHERE idempotency_key = $1;
  `;
  await db.query(sql, [idempotencyKey, responseStatus, JSON.stringify(responsePayload)]);
}

async function fail(idempotencyKey, responseStatus, responsePayload) {
  const sql = `
    UPDATE idempotency_keys
    SET status = 'FAILED',
        response_status = $2,
        response_payload = $3,
        completed_at = CURRENT_TIMESTAMP
    WHERE idempotency_key = $1;
  `;
  await db.query(sql, [idempotencyKey, responseStatus || null, responsePayload ? JSON.stringify(responsePayload) : null]);
}

module.exports = {
  computeHash,
  claim,
  complete,
  fail,
};
