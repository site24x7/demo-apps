'use strict';
const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert/strict');

const transferOrchestrator = require('../src/services/transferOrchestrator');
const idempotencyRepo = require('../src/repositories/idempotencyRepository');
const kafkaProducer = require('../src/kafka/producer');
const httpClient = require('../src/utils/httpClient');
const db = require('../src/db/pool');

describe('Transfer Orchestrator Flow', () => {
  let inMemoryKeys = new Map();
  let kafkaEvents = [];
  let httpCalls = [];
  let riskMockHandler = null;
  let ledgerMockHandler = null;

  beforeEach(() => {
    inMemoryKeys.clear();
    kafkaEvents = [];
    httpCalls = [];
    riskMockHandler = null;
    ledgerMockHandler = null;

    // Mock db.query for idempotency repository
    db.query = async (sql, params) => {
      const trimmed = sql.trim();
      if (trimmed.startsWith('INSERT INTO idempotency_keys')) {
        const [key, hash, status] = params;
        if (inMemoryKeys.has(key)) return { rows: [] };
        const row = {
          idempotency_key: key,
          request_hash: hash,
          status: status || 'IN_PROGRESS',
          response_status: null,
          response_payload: null,
          created_at: new Date().toISOString(),
          completed_at: null,
        };
        inMemoryKeys.set(key, row);
        return { rows: [row] };
      }
      if (trimmed.startsWith('SELECT * FROM idempotency_keys')) {
        const [key] = params;
        const row = inMemoryKeys.get(key);
        return { rows: row ? [row] : [] };
      }
      if (trimmed.includes("SET status = 'COMPLETED'")) {
        const [key, status, payload] = params;
        const row = inMemoryKeys.get(key);
        if (row) {
          row.status = 'COMPLETED';
          row.response_status = status;
          row.response_payload = JSON.parse(payload);
        }
        return { rows: row ? [row] : [] };
      }
      if (trimmed.includes("SET status = 'FAILED'")) {
        const [key, status, payload] = params;
        const row = inMemoryKeys.get(key);
        if (row) {
          row.status = 'FAILED';
          row.response_status = status;
          row.response_payload = payload ? JSON.parse(payload) : null;
        }
        return { rows: row ? [row] : [] };
      }
      return { rows: [] };
    };

    // Mock Kafka producer
    kafkaProducer.sendEvent = async (event) => {
      kafkaEvents.push(event);
      return event;
    };

    // Mock httpClient.callHttp
    httpClient.callHttp = async (opts) => {
      httpCalls.push(opts);
      if (opts.url.includes('/api/v1/risk/evaluate')) {
        if (riskMockHandler) return riskMockHandler(opts);
        return {
          data: {
            risk_score: 10,
            decision: 'APPROVED',
            reasons: [],
            evaluated_at: new Date().toISOString(),
          },
        };
      }
      if (opts.url.includes('/api/v1/ledger/transfer')) {
        if (ledgerMockHandler) return ledgerMockHandler(opts);
        return {
          data: {
            journal_id: 'jour-101',
            transaction_ref: 'tx-202',
            transaction_type: 'P2P_TRANSFER',
            from_account: opts.data.from_account,
            to_account: opts.data.to_account,
            amount: opts.data.amount,
            from_balance_after: '8400.00',
            to_balance_after: '5300.00',
            counterparty_name: 'Bob Smith',
            created_at: new Date().toISOString(),
          },
        };
      }
      throw new Error(`Unexpected HTTP call: ${opts.url}`);
    };
  });

  test('requires Idempotency-Key header', async () => {
    await assert.rejects(
      async () => {
        await transferOrchestrator.orchestrateTransfer({
          idempotencyKey: null,
          fromAccount: '2170000001',
          toAccount: '2170000002',
          amount: '100.00',
          pin: '1234',
        });
      },
      (err) => {
        assert.equal(err.code, 'IDEMPOTENCY_KEY_REQUIRED');
        assert.equal(err.status, 400);
        return true;
      }
    );
  });

  test('rejects transfer to the same account', async () => {
    await assert.rejects(
      async () => {
        await transferOrchestrator.orchestrateTransfer({
          idempotencyKey: 'key-same-account',
          fromAccount: '2170000001',
          toAccount: '2170000001',
          amount: '50.00',
          pin: '1234',
        });
      },
      (err) => {
        assert.equal(err.code, 'SAME_ACCOUNT');
        assert.equal(err.status, 400);
        return true;
      }
    );
  });

  test('executes successful end-to-end transfer (happy path)', async () => {
    const result = await transferOrchestrator.orchestrateTransfer({
      idempotencyKey: 'key-happy-path',
      fromAccount: '2170000001',
      toAccount: '2170000002',
      amount: '100.00',
      description: 'Dinner payment',
      pin: '1234',
      userToken: 'fake-jwt-token',
      userName: 'Alice Johnson',
      correlationId: 'corr-123',
    });

    assert.equal(result.replayed, false);
    assert.equal(result.statusCode, 200);
    assert.equal(result.data.status, 'COMPLETED');
    assert.equal(result.data.transaction_ref, 'tx-202');
    assert.equal(result.data.journal_id, 'jour-101');
    assert.equal(result.data.amount, '100.00');
    assert.equal(result.data.new_balance, '8400.00');
    assert.equal(result.data.recipient_name, 'Bob Smith');
    assert.equal(result.data.risk.decision, 'APPROVED');

    // Kafka event should have been emitted
    assert.equal(kafkaEvents.length, 1);
    assert.equal(kafkaEvents[0].eventType, 'TransferCompleted');
    assert.equal(kafkaEvents[0].key, '2170000001');
    assert.equal(kafkaEvents[0].data.transaction_ref, 'tx-202');

    // Stored in idempotency repo
    assert.equal(inMemoryKeys.get('key-happy-path').status, 'COMPLETED');
  });

  test('blocks transfer when AI risk decision is BLOCKED without calling ledger', async () => {
    riskMockHandler = () => {
      return {
        data: {
          risk_score: 85,
          decision: 'BLOCKED',
          reasons: [{ rule: 'HIGH_VELOCITY', points: 60, detail: 'Too many transfers' }],
        },
      };
    };

    let ledgerCalled = false;
    ledgerMockHandler = () => {
      ledgerCalled = true;
      return { data: {} };
    };

    await assert.rejects(
      async () => {
        await transferOrchestrator.orchestrateTransfer({
          idempotencyKey: 'key-risk-blocked',
          fromAccount: '2170000001',
          toAccount: '2170000002',
          amount: '9000.00',
          pin: '1234',
          userToken: 'fake-jwt',
          userName: 'Alice',
        });
      },
      (err) => {
        assert.equal(err.code, 'TRANSFER_BLOCKED');
        assert.equal(err.status, 403);
        assert.equal(err.extra?.risk?.decision, 'BLOCKED');
        assert.equal(err.extra?.risk?.score, 85);
        return true;
      }
    );

    assert.equal(ledgerCalled, false, 'Ledger must not be called when risk blocks transfer');
    assert.equal(inMemoryKeys.get('key-risk-blocked').status, 'FAILED');
  });

  test('fails open when AI risk service is unavailable / times out', async () => {
    // Risk service fails with timeout / connection error
    riskMockHandler = () => {
      throw new Error('connect ECONNREFUSED 127.0.0.1:8083');
    };

    const result = await transferOrchestrator.orchestrateTransfer({
      idempotencyKey: 'key-risk-failopen',
      fromAccount: '2170000001',
      toAccount: '2170000002',
      amount: '50.00',
      pin: '1234',
      userToken: 'fake-jwt',
      userName: 'Alice',
    });

    assert.equal(result.statusCode, 200);
    assert.equal(result.data.status, 'COMPLETED');
    assert.equal(result.data.risk.decision, 'APPROVED');
    assert.equal(result.data.risk.score, 0);
    assert.equal(result.data.risk.reasons[0].rule, 'FAIL_OPEN');
    assert.equal(kafkaEvents.length, 1);
  });

  test('passes through ledger errors with status and error body', async () => {
    ledgerMockHandler = () => {
      const err = new Error('Request failed with status code 422');
      err.response = {
        status: 422,
        data: {
          error: 'INSUFFICIENT_FUNDS',
          message: 'Account balance insufficient for requested transfer',
        },
      };
      throw err;
    };

    await assert.rejects(
      async () => {
        await transferOrchestrator.orchestrateTransfer({
          idempotencyKey: 'key-insufficient-funds',
          fromAccount: '2170000001',
          toAccount: '2170000002',
          amount: '99999.00',
          pin: '1234',
          userToken: 'fake-jwt',
          userName: 'Alice',
        });
      },
      (err) => {
        assert.equal(err.status, 422);
        assert.equal(err.code, 'INSUFFICIENT_FUNDS');
        assert.equal(err.message, 'Account balance insufficient for requested transfer');
        return true;
      }
    );

    assert.equal(inMemoryKeys.get('key-insufficient-funds').status, 'FAILED');
  });

  test('replays cached response for identical idempotency key and payload', async () => {
    // First call
    const firstResult = await transferOrchestrator.orchestrateTransfer({
      idempotencyKey: 'key-replay-test',
      fromAccount: '2170000001',
      toAccount: '2170000002',
      amount: '75.00',
      pin: '1234',
      userToken: 'fake-jwt',
      userName: 'Alice',
    });
    assert.equal(firstResult.replayed, false);
    assert.equal(httpCalls.length, 2); // 1 risk + 1 ledger

    // Second call with same key and body
    const secondResult = await transferOrchestrator.orchestrateTransfer({
      idempotencyKey: 'key-replay-test',
      fromAccount: '2170000001',
      toAccount: '2170000002',
      amount: '75.00',
      pin: '1234',
      userToken: 'fake-jwt',
      userName: 'Alice',
    });

    assert.equal(secondResult.replayed, true);
    assert.equal(secondResult.statusCode, 200);
    assert.equal(secondResult.data.transaction_ref, firstResult.data.transaction_ref);
    // Neither risk nor ledger was called a second time
    assert.equal(httpCalls.length, 2);
  });
});
