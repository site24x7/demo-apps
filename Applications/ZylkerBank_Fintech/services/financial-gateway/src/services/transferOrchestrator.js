'use strict';
const { config } = require('../config');
const idempotencyRepo = require('../repositories/idempotencyRepository');
const kafkaProducer = require('../kafka/producer');
const httpClient = require('../utils/httpClient');
const { normalizeAmount, fmt } = require('../utils/money');
const { badRequest, forbidden, AppError } = require('../errors');
const logger = require('../logger');

async function evaluateRisk({ fromAccount, toAccount, amount, correlationId, traceparent, tracestate }) {
  try {
    const res = await httpClient.callHttp({
      method: 'POST',
      url: `${config.riskUrl}/api/v1/risk/evaluate`,
      data: {
        from_account: fromAccount,
        to_account: toAccount,
        amount,
        timestamp: new Date().toISOString(),
        correlation_id: correlationId,
      },
      headers: {
        'X-Internal-Token': config.internalToken,
      },
      timeout: config.riskTimeoutMs,
      correlationId,
      traceparent,
      tracestate,
    });

    return res.data;
  } catch (err) {
    // Fail-open per CONTRACTS.md
    logger.warn('Risk service evaluation failed or timed out, failing open', {
      error: err.message,
      riskUrl: config.riskUrl,
    });
    return {
      risk_score: 0,
      decision: 'APPROVED',
      reasons: [
        {
          rule: 'FAIL_OPEN',
          points: 0,
          detail: 'Risk service unavailable, fail-open approved',
        },
      ],
      evaluated_at: new Date().toISOString(),
    };
  }
}

async function executeLedgerTransfer({
  idempotencyKey,
  fromAccount,
  toAccount,
  amount,
  description,
  pin,
  userToken,
  correlationId,
  traceparent,
  tracestate,
}) {
  try {
    const res = await httpClient.callHttp({
      method: 'POST',
      url: `${config.ledgerUrl}/api/v1/ledger/transfer`,
      data: {
        idempotency_key: idempotencyKey,
        from_account: fromAccount,
        to_account: toAccount,
        amount,
        description: description || 'P2P Transfer',
        transaction_type: 'P2P_TRANSFER',
        pin,
      },
      headers: {
        Authorization: `Bearer ${userToken}`,
      },
      timeout: config.ledgerTimeoutMs,
      correlationId,
      traceparent,
      tracestate,
    });

    return res.data;
  } catch (err) {
    if (err.response) {
      const { status, data } = err.response;
      logger.warn('Ledger transfer returned error', { status, data });
      throw new AppError(
        status,
        data?.error || 'LEDGER_ERROR',
        data?.message || 'Ledger transfer failed',
        data
      );
    }
    logger.error('Ledger service unreachable or timed out', { error: err.message });
    throw new AppError(502, 'LEDGER_UNAVAILABLE', 'Ledger service is unavailable');
  }
}

async function orchestrateTransfer({
  idempotencyKey,
  fromAccount,
  toAccount,
  amount,
  description,
  pin,
  userToken,
  userName,
  correlationId,
  traceparent,
  tracestate,
}) {
  if (!idempotencyKey) {
    throw badRequest('IDEMPOTENCY_KEY_REQUIRED', 'Idempotency-Key header is required');
  }

  const normalizedAmount = normalizeAmount(amount);

  if (fromAccount === toAccount) {
    throw badRequest('SAME_ACCOUNT', 'Cannot transfer funds to the same account');
  }

  // Idempotency claim
  const requestHash = idempotencyRepo.computeHash(fromAccount, {
    to_account: toAccount,
    amount: normalizedAmount,
    description: description || '',
    pin,
  });

  const claimResult = await idempotencyRepo.claim(
    idempotencyKey,
    requestHash,
    config.idempotencyStaleSeconds
  );

  if (claimResult.replayed) {
    logger.info('Idempotent transfer replayed', { idempotencyKey, fromAccount });
    return {
      replayed: true,
      statusCode: claimResult.status || 200,
      data: claimResult.payload,
    };
  }

  // Step 1: Pre-flight risk evaluation (fail-open)
  const riskResult = await evaluateRisk({
    fromAccount,
    toAccount,
    amount: normalizedAmount,
    correlationId,
    traceparent,
    tracestate,
  });

  if (riskResult.decision === 'BLOCKED') {
    logger.warn('Transfer blocked by risk assessment', {
      fromAccount,
      toAccount,
      riskResult,
    });
    const errorBody = {
      risk: {
        score: riskResult.risk_score || 0,
        decision: riskResult.decision,
        reasons: riskResult.reasons || [],
      },
    };
    await idempotencyRepo.fail(idempotencyKey, 403, errorBody);
    throw forbidden('TRANSFER_BLOCKED', 'Transfer blocked by risk assessment', errorBody);
  }

  // Step 2: Atomic financial transfer in Core Ledger
  let ledgerData;
  try {
    ledgerData = await executeLedgerTransfer({
      idempotencyKey,
      fromAccount,
      toAccount,
      amount: normalizedAmount,
      description,
      pin,
      userToken,
      correlationId,
      traceparent,
      tracestate,
    });
  } catch (err) {
    await idempotencyRepo.fail(idempotencyKey, err.status || 500, err.toBody ? err.toBody() : null);
    throw err;
  }

  // Step 3: Kafka event publish (best-effort)
  kafkaProducer.sendEvent({
    topic: config.kafka.transfersTopic,
    key: fromAccount,
    eventType: 'TransferCompleted',
    correlationId,
    data: {
      transaction_ref: ledgerData.transaction_ref,
      journal_id: ledgerData.journal_id,
      from_account: fromAccount,
      to_account: toAccount,
      from_name: userName || fromAccount,
      to_name: ledgerData.counterparty_name || toAccount,
      amount: normalizedAmount,
      currency: 'USD',
      description: description || '',
      risk_score: riskResult.risk_score || 0,
      risk_decision: riskResult.decision || 'APPROVED',
    },
  });

  // Step 4: Construct response payload
  const responsePayload = {
    status: 'COMPLETED',
    transaction_ref: ledgerData.transaction_ref,
    journal_id: ledgerData.journal_id,
    amount: normalizedAmount,
    currency: 'USD',
    from_account: fromAccount,
    to_account: toAccount,
    recipient_name: ledgerData.counterparty_name || toAccount,
    description: description || '',
    risk: {
      score: riskResult.risk_score || 0,
      decision: riskResult.decision || 'APPROVED',
      reasons: riskResult.reasons || [],
    },
    new_balance: fmt(ledgerData.from_balance_after),
    created_at: ledgerData.created_at || new Date().toISOString(),
  };

  // Mark idempotency key COMPLETED
  await idempotencyRepo.complete(idempotencyKey, 200, responsePayload);

  return {
    replayed: false,
    statusCode: 200,
    data: responsePayload,
  };
}

module.exports = {
  orchestrateTransfer,
  evaluateRisk,
  executeLedgerTransfer,
};
