'use strict';
const cardService = require('../services/cardService');

async function listCards(req, res, next) {
  try {
    const result = await cardService.listCards(req.user.userId);
    return res.status(200).json(result);
  } catch (err) {
    return next(err);
  }
}

async function getCard(req, res, next) {
  try {
    const result = await cardService.getCard(req.params.id, req.user.userId);
    return res.status(200).json(result);
  } catch (err) {
    return next(err);
  }
}

async function createCard(req, res, next) {
  try {
    const result = await cardService.createCard({
      userId: req.user.userId,
      accountNumber: req.user.account_number,
      userName: req.user.name,
      cardType: req.body.card_type,
      spendingLimit: req.body.spending_limit,
      correlationId: req.correlationId,
    });
    return res.status(201).json(result);
  } catch (err) {
    return next(err);
  }
}

async function fundCard(req, res, next) {
  try {
    const idempotencyKey = req.headers['idempotency-key'];
    const result = await cardService.fundCard({
      cardId: req.params.id,
      userId: req.user.userId,
      accountNumber: req.user.account_number,
      amount: req.body.amount,
      pin: req.body.pin,
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

async function withdrawCard(req, res, next) {
  try {
    const idempotencyKey = req.headers['idempotency-key'];
    const result = await cardService.withdrawCard({
      cardId: req.params.id,
      userId: req.user.userId,
      accountNumber: req.user.account_number,
      amount: req.body.amount,
      pin: req.body.pin,
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

async function updateCardStatus(req, res, next) {
  try {
    const isFrozen = typeof req.body.frozen === 'boolean' ? req.body.frozen : req.body.is_frozen;
    const result = await cardService.updateCardStatus({
      cardId: req.params.id,
      userId: req.user.userId,
      accountNumber: req.user.account_number,
      isFrozen,
      correlationId: req.correlationId,
    });
    return res.status(200).json(result);
  } catch (err) {
    return next(err);
  }
}

module.exports = {
  listCards,
  getCard,
  createCard,
  fundCard,
  withdrawCard,
  updateCardStatus,
};
