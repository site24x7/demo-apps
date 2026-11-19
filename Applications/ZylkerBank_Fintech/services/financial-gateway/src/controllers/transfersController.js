'use strict';
const transferOrchestrator = require('../services/transferOrchestrator');
const paymentRequestService = require('../services/paymentRequestService');

async function initiateTransfer(req, res, next) {
  try {
    const idempotencyKey = req.headers['idempotency-key'];
    const result = await transferOrchestrator.orchestrateTransfer({
      idempotencyKey,
      fromAccount: req.user.account_number,
      toAccount: req.body.to_account,
      amount: req.body.amount,
      description: req.body.description,
      pin: req.body.pin,
      userToken: req.user.rawToken,
      userName: req.user.name,
      correlationId: req.correlationId,
      traceparent: req.headers['traceparent'],
      tracestate: req.headers['tracestate'],
    });

    if (result.replayed) {
      res.setHeader('Idempotency-Replayed', 'true');
    }

    return res.status(result.statusCode).json(result.data);
  } catch (err) {
    return next(err);
  }
}

async function createPaymentRequest(req, res, next) {
  try {
    const result = await paymentRequestService.createPaymentRequest({
      requesterAccount: req.user.account_number,
      requesterName: req.user.name,
      payerAccount: req.body.payer_account,
      amount: req.body.amount,
      description: req.body.description,
      userToken: req.user.rawToken,
      correlationId: req.correlationId,
    });
    return res.status(201).json(result);
  } catch (err) {
    return next(err);
  }
}

async function listPaymentRequests(req, res, next) {
  try {
    const result = await paymentRequestService.listPaymentRequests(req.user.account_number);
    return res.status(200).json(result);
  } catch (err) {
    return next(err);
  }
}

async function settlePaymentRequest(req, res, next) {
  try {
    const idempotencyKey = req.headers['idempotency-key'];
    const result = await paymentRequestService.settlePaymentRequest({
      requestId: req.params.id,
      pin: req.body.pin,
      userAccount: req.user.account_number,
      userName: req.user.name,
      userToken: req.user.rawToken,
      idempotencyKey,
      correlationId: req.correlationId,
      traceparent: req.headers['traceparent'],
      tracestate: req.headers['tracestate'],
    });
    return res.status(200).json(result);
  } catch (err) {
    return next(err);
  }
}

async function declinePaymentRequest(req, res, next) {
  try {
    const result = await paymentRequestService.declinePaymentRequest({
      requestId: req.params.id,
      userAccount: req.user.account_number,
    });
    return res.status(200).json(result);
  } catch (err) {
    return next(err);
  }
}

module.exports = {
  initiateTransfer,
  createPaymentRequest,
  listPaymentRequests,
  settlePaymentRequest,
  declinePaymentRequest,
};
