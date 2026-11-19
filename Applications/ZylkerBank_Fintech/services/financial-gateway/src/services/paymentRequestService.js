'use strict';
const paymentRequestsRepo = require('../repositories/paymentRequestsRepository');
const transferOrchestrator = require('./transferOrchestrator');
const kafkaProducer = require('../kafka/producer');
const { config } = require('../config');
const httpClient = require('../utils/httpClient');
const { normalizeAmount, fmt } = require('../utils/money');
const { badRequest, forbidden, notFound } = require('../errors');
const logger = require('../logger');

async function lookupAccountOwner(accountNumber, userToken) {
  try {
    const res = await httpClient.callHttp({
      method: 'GET',
      url: `${config.ledgerUrl}/api/v1/accounts/${accountNumber}`,
      headers: {
        'X-Internal-Token': config.internalToken,
        ...(userToken ? { Authorization: `Bearer ${userToken}` } : {}),
      },
      timeout: 2000,
    });
    return res.data?.owner_name || null;
  } catch (err) {
    logger.debug('Could not lookup account owner name (non-fatal)', {
      accountNumber,
      error: err.message,
    });
    return null;
  }
}

async function createPaymentRequest({
  requesterAccount,
  requesterName,
  payerAccount,
  amount,
  description,
  userToken,
  correlationId,
}) {
  if (requesterAccount === payerAccount) {
    throw badRequest('SAME_ACCOUNT', 'Cannot request money from your own account');
  }

  const normalizedAmount = normalizeAmount(amount);
  const payerName = await lookupAccountOwner(payerAccount, userToken);

  const row = await paymentRequestsRepo.create({
    requesterAccount,
    requesterName,
    payerAccount,
    payerName,
    amount: normalizedAmount,
    description,
  });

  const formatted = paymentRequestsRepo.formatPaymentRequest(row);

  kafkaProducer.sendEvent({
    topic: config.kafka.transfersTopic,
    key: payerAccount,
    eventType: 'PaymentRequested',
    correlationId,
    data: {
      request_id: formatted.request_id,
      requester_account: requesterAccount,
      requester_name: requesterName,
      payer_account: payerAccount,
      payer_name: payerName,
      amount: normalizedAmount,
      currency: 'USD',
      description: description || '',
    },
  });

  return formatted;
}

async function listPaymentRequests(accountNumber) {
  return paymentRequestsRepo.listByUserAccount(accountNumber);
}

async function settlePaymentRequest({
  requestId,
  pin,
  userAccount,
  userName,
  userToken,
  idempotencyKey,
  correlationId,
  traceparent,
  tracestate,
}) {
  const row = await paymentRequestsRepo.getById(requestId);
  if (!row) {
    throw notFound('REQUEST_NOT_FOUND', 'Payment request not found');
  }

  if (row.payer_account !== userAccount) {
    throw forbidden('FORBIDDEN', 'Only the requested payer can settle this payment request');
  }

  if (row.status !== 'REQUEST_SENT') {
    throw badRequest(
      'INVALID_REQUEST_STATUS',
      `Payment request cannot be settled because it is already ${row.status.toLowerCase()}`
    );
  }

  // Orchestrate transfer from payer to requester
  const effectiveIdempotencyKey = idempotencyKey || `settle-${requestId}`;
  const transferResult = await transferOrchestrator.orchestrateTransfer({
    idempotencyKey: effectiveIdempotencyKey,
    fromAccount: userAccount,
    toAccount: row.requester_account,
    amount: row.amount,
    description: row.description || `Settlement for payment request ${requestId}`,
    pin,
    userToken,
    userName,
    correlationId,
    traceparent,
    tracestate,
  });

  const txRef = transferResult.data.transaction_ref;
  const updatedRow = await paymentRequestsRepo.settle(requestId, txRef);
  const formattedRequest = paymentRequestsRepo.formatPaymentRequest(updatedRow);

  kafkaProducer.sendEvent({
    topic: config.kafka.transfersTopic,
    key: userAccount,
    eventType: 'PaymentSettled',
    correlationId,
    data: {
      request_id: requestId,
      transaction_ref: txRef,
      payer_account: userAccount,
      requester_account: row.requester_account,
      amount: fmt(row.amount),
    },
  });

  return {
    request: formattedRequest,
    transfer: transferResult.data,
  };
}

async function declinePaymentRequest({ requestId, userAccount }) {
  const row = await paymentRequestsRepo.getById(requestId);
  if (!row) {
    throw notFound('REQUEST_NOT_FOUND', 'Payment request not found');
  }

  if (row.payer_account !== userAccount) {
    throw forbidden('FORBIDDEN', 'Only the requested payer can decline this payment request');
  }

  if (row.status !== 'REQUEST_SENT') {
    throw badRequest(
      'INVALID_REQUEST_STATUS',
      `Payment request cannot be declined because it is already ${row.status.toLowerCase()}`
    );
  }

  const updatedRow = await paymentRequestsRepo.decline(requestId);
  return paymentRequestsRepo.formatPaymentRequest(updatedRow);
}

module.exports = {
  createPaymentRequest,
  listPaymentRequests,
  settlePaymentRequest,
  declinePaymentRequest,
};
