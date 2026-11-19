'use strict';
const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const idempotencyRepo = require('../src/repositories/idempotencyRepository');
const db = require('../src/db/pool');

describe('Idempotency State Machine', () => {
  let inMemoryTable = new Map();

  beforeEach(() => {
    inMemoryTable.clear();

    // Mock db.query to simulate PostgreSQL idempotency_keys table
    db.query = async (sql, params) => {
      const trimmed = sql.trim();

      // INSERT ON CONFLICT DO NOTHING
      if (trimmed.startsWith('INSERT INTO idempotency_keys')) {
        const [key, hash, status] = params;
        if (inMemoryTable.has(key)) {
          return { rows: [] };
        }
        const row = {
          idempotency_key: key,
          request_hash: hash,
          status: status || 'IN_PROGRESS',
          response_status: null,
          response_payload: null,
          created_at: new Date().toISOString(),
          completed_at: null,
        };
        inMemoryTable.set(key, row);
        return { rows: [row] };
      }

      // SELECT
      if (trimmed.startsWith('SELECT * FROM idempotency_keys')) {
        const [key] = params;
        const row = inMemoryTable.get(key);
        return { rows: row ? [row] : [] };
      }

      // UPDATE status = 'COMPLETED'
      if (trimmed.includes("SET status = 'COMPLETED'")) {
        const [key, status, payload] = params;
        const row = inMemoryTable.get(key);
        if (row) {
          row.status = 'COMPLETED';
          row.response_status = status;
          row.response_payload = JSON.parse(payload);
          row.completed_at = new Date().toISOString();
        }
        return { rows: row ? [row] : [] };
      }

      // UPDATE status = 'FAILED'
      if (trimmed.includes("SET status = 'FAILED'")) {
        const [key, status, payload] = params;
        const row = inMemoryTable.get(key);
        if (row) {
          row.status = 'FAILED';
          row.response_status = status;
          row.response_payload = payload ? JSON.parse(payload) : null;
          row.completed_at = new Date().toISOString();
        }
        return { rows: row ? [row] : [] };
      }

      // UPDATE status = 'IN_PROGRESS' (stale recovery or retry)
      if (trimmed.includes("SET status = 'IN_PROGRESS'")) {
        const [key] = params;
        const row = inMemoryTable.get(key);
        if (row) {
          row.status = 'IN_PROGRESS';
          row.created_at = new Date().toISOString();
          return { rows: [row] };
        }
        return { rows: [] };
      }

      return { rows: [] };
    };
  });

  test('computeHash is deterministic regardless of body key ordering', () => {
    const hash1 = idempotencyRepo.computeHash('2170000001', {
      to_account: '2170000002',
      amount: '100.00',
      pin: '1234',
    });
    const hash2 = idempotencyRepo.computeHash('2170000001', {
      amount: '100.00',
      pin: '1234',
      to_account: '2170000002',
    });
    assert.equal(hash1, hash2);
  });

  test('claim succeeds on first attempt', async () => {
    const key = 'test-key-1';
    const hash = 'hash-1';
    const result = await idempotencyRepo.claim(key, hash, 120);
    assert.equal(result.claimed, true);
    assert.equal(inMemoryTable.get(key).status, 'IN_PROGRESS');
  });

  test('claim throws 422 IDEMPOTENCY_KEY_REUSED when key is reused with different hash', async () => {
    const key = 'test-key-2';
    await idempotencyRepo.claim(key, 'hash-original', 120);

    await assert.rejects(
      async () => {
        await idempotencyRepo.claim(key, 'hash-different', 120);
      },
      (err) => {
        assert.equal(err.code, 'IDEMPOTENCY_KEY_REUSED');
        assert.equal(err.status, 422);
        return true;
      }
    );
  });

  test('claim returns cached response when existing key is COMPLETED (replay)', async () => {
    const key = 'test-key-3';
    const hash = 'hash-3';
    await idempotencyRepo.claim(key, hash, 120);
    await idempotencyRepo.complete(key, 200, { transaction_ref: 'tx-123', status: 'COMPLETED' });

    const replayResult = await idempotencyRepo.claim(key, hash, 120);
    assert.equal(replayResult.claimed, false);
    assert.equal(replayResult.replayed, true);
    assert.equal(replayResult.status, 200);
    assert.equal(replayResult.payload.transaction_ref, 'tx-123');
  });

  test('claim throws 409 IDEMPOTENCY_IN_PROGRESS when request is already in-flight and not stale', async () => {
    const key = 'test-key-4';
    const hash = 'hash-4';
    await idempotencyRepo.claim(key, hash, 120);

    await assert.rejects(
      async () => {
        await idempotencyRepo.claim(key, hash, 120);
      },
      (err) => {
        assert.equal(err.code, 'IDEMPOTENCY_IN_PROGRESS');
        assert.equal(err.status, 409);
        return true;
      }
    );
  });

  test('claim recovers stale IN_PROGRESS key older than staleSeconds', async () => {
    const key = 'test-key-5';
    const hash = 'hash-5';
    await idempotencyRepo.claim(key, hash, 120);

    // Make it 3 minutes old (stale)
    const row = inMemoryTable.get(key);
    row.created_at = new Date(Date.now() - 180 * 1000).toISOString();

    const result = await idempotencyRepo.claim(key, hash, 120);
    assert.equal(result.claimed, true);
    assert.equal(result.staleRecovered, true);
  });

  test('claim allows retrying a previously FAILED key', async () => {
    const key = 'test-key-6';
    const hash = 'hash-6';
    await idempotencyRepo.claim(key, hash, 120);
    await idempotencyRepo.fail(key, 500, { error: 'INTERNAL_ERROR' });

    const result = await idempotencyRepo.claim(key, hash, 120);
    assert.equal(result.claimed, true);
    assert.equal(result.retryingFailed, true);
  });
});
