'use strict';
const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert/strict');

const paymentRequestService = require('../src/services/paymentRequestService');
const transferOrchestrator = require('../src/services/transferOrchestrator');
const kafkaProducer = require('../src/kafka/producer');
const db = require('../src/db/pool');

describe('Payment Requests Service', () => {
  let inMemoryRequests = new Map();
  let kafkaEvents = [];

  beforeEach(() => {
    inMemoryRequests.clear();
    kafkaEvents = [];

    // Mock db.query for payment requests
    db.query = async (sql, params) => {
      const trimmed = sql.trim();
      if (trimmed.startsWith('INSERT INTO payment_requests')) {
        const [requester, requesterName, payer, payerName, amount, description] = params;
        const requestId = 'req-' + (inMemoryRequests.size + 1);
        const row = {
          request_id: requestId,
          requester_account: requester,
          requester_name: requesterName,
          payer_account: payer,
          payer_name: payerName,
          amount: amount,
          currency: 'USD',
          description: description,
          status: 'REQUEST_SENT',
          transaction_ref: null,
          created_at: new Date().toISOString(),
          settled_at: null,
        };
        inMemoryRequests.set(requestId, row);
        return { rows: [row] };
      }
      if (trimmed.startsWith('SELECT * FROM payment_requests WHERE request_id = $1')) {
        const [requestId] = params;
        const row = inMemoryRequests.get(requestId);
        return { rows: row ? [row] : [] };
      }
      if (trimmed.includes('WHERE payer_account = $1')) {
        const [account] = params;
        const rows = [];
        for (const req of inMemoryRequests.values()) {
          if (req.payer_account === account) rows.push(req);
        }
        return { rows };
      }
      if (trimmed.includes('WHERE requester_account = $1')) {
        const [account] = params;
        const rows = [];
        for (const req of inMemoryRequests.values()) {
          if (req.requester_account === account) rows.push(req);
        }
        return { rows };
      }
      if (trimmed.includes("SET status = 'REQUEST_SETTLED'")) {
        const [requestId, txRef] = params;
        const row = inMemoryRequests.get(requestId);
        if (row) {
          row.status = 'REQUEST_SETTLED';
          row.transaction_ref = txRef;
          row.settled_at = new Date().toISOString();
          return { rows: [row] };
        }
        return { rows: [] };
      }
      if (trimmed.includes("SET status = 'DECLINED'")) {
        const [requestId] = params;
        const row = inMemoryRequests.get(requestId);
        if (row) {
          row.status = 'DECLINED';
          row.settled_at = new Date().toISOString();
          return { rows: [row] };
        }
        return { rows: [] };
      }
      return { rows: [] };
    };

    kafkaProducer.sendEvent = async (event) => {
      kafkaEvents.push(event);
      return event;
    };
  });

  test('createPaymentRequest creates money request from another account', async () => {
    const result = await paymentRequestService.createPaymentRequest({
      requesterAccount: '2170000001',
      requesterName: 'Alice Johnson',
      payerAccount: '2170000002',
      amount: '50.00',
      description: 'Lunch split',
    });

    assert.ok(result.request_id);
    assert.equal(result.requester_account, '2170000001');
    assert.equal(result.payer_account, '2170000002');
    assert.equal(result.amount, '50.00');
    assert.equal(result.status, 'REQUEST_SENT');

    assert.equal(kafkaEvents.length, 1);
    assert.equal(kafkaEvents[0].eventType, 'PaymentRequested');
  });

  test('createPaymentRequest rejects requesting money from own account', async () => {
    await assert.rejects(
      async () => {
        await paymentRequestService.createPaymentRequest({
          requesterAccount: '2170000001',
          requesterName: 'Alice',
          payerAccount: '2170000001',
          amount: '10.00',
        });
      },
      (err) => {
        assert.equal(err.code, 'SAME_ACCOUNT');
        assert.equal(err.status, 400);
        return true;
      }
    );
  });

  test('listPaymentRequests categorizes incoming and outgoing requests', async () => {
    await paymentRequestService.createPaymentRequest({
      requesterAccount: '2170000001',
      requesterName: 'Alice',
      payerAccount: '2170000002',
      amount: '30.00',
    });

    await paymentRequestService.createPaymentRequest({
      requesterAccount: '2170000003',
      requesterName: 'Charlie',
      payerAccount: '2170000001',
      amount: '15.00',
    });

    const aliceRequests = await paymentRequestService.listPaymentRequests('2170000001');
    assert.equal(aliceRequests.outgoing.length, 1);
    assert.equal(aliceRequests.outgoing[0].payer_account, '2170000002');
    assert.equal(aliceRequests.incoming.length, 1);
    assert.equal(aliceRequests.incoming[0].requester_account, '2170000003');
  });

  test('settlePaymentRequest enforces payer authorization and executes transfer', async () => {
    const created = await paymentRequestService.createPaymentRequest({
      requesterAccount: '2170000001',
      requesterName: 'Alice',
      payerAccount: '2170000002',
      amount: '40.00',
    });

    // Unauthorized caller attempts to settle
    await assert.rejects(
      async () => {
        await paymentRequestService.settlePaymentRequest({
          requestId: created.request_id,
          pin: '1234',
          userAccount: '2170000003', // Charlie is not the payer
          userName: 'Charlie',
          userToken: 'token',
        });
      },
      (err) => {
        assert.equal(err.code, 'FORBIDDEN');
        assert.equal(err.status, 403);
        return true;
      }
    );

    // Mock transferOrchestrator
    const originalOrchestrate = transferOrchestrator.orchestrateTransfer;
    transferOrchestrator.orchestrateTransfer = async () => ({
      statusCode: 200,
      data: {
        transaction_ref: 'tx-settled-1',
        status: 'COMPLETED',
        amount: '40.00',
      },
    });

    try {
      const settled = await paymentRequestService.settlePaymentRequest({
        requestId: created.request_id,
        pin: '1234',
        userAccount: '2170000002',
        userName: 'Bob Smith',
        userToken: 'token',
      });

      assert.equal(settled.request.status, 'REQUEST_SETTLED');
      assert.equal(settled.request.transaction_ref, 'tx-settled-1');
      assert.equal(settled.transfer.transaction_ref, 'tx-settled-1');

      const settledEvent = kafkaEvents.find((e) => e.eventType === 'PaymentSettled');
      assert.ok(settledEvent);
      assert.equal(settledEvent.data.transaction_ref, 'tx-settled-1');
    } finally {
      transferOrchestrator.orchestrateTransfer = originalOrchestrate;
    }
  });

  test('declinePaymentRequest marks request DECLINED', async () => {
    const created = await paymentRequestService.createPaymentRequest({
      requesterAccount: '2170000001',
      requesterName: 'Alice',
      payerAccount: '2170000002',
      amount: '25.00',
    });

    const declined = await paymentRequestService.declinePaymentRequest({
      requestId: created.request_id,
      userAccount: '2170000002',
    });

    assert.equal(declined.status, 'DECLINED');
  });
});
