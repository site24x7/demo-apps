'use strict';
const db = require('../db/pool');
const cardsRepo = require('../repositories/cardsRepository');
const kafkaProducer = require('../kafka/producer');
const { config } = require('../config');
const { generatePan } = require('../utils/luhn');
const { generateCvv, hashCvv, encryptPan, maskPan } = require('../utils/cardCrypto');
const { normalizeAmount, fmt } = require('../utils/money');
const httpClient = require('../utils/httpClient');
const { notFound, conflict, unprocessable, badRequest, AppError } = require('../errors');
const logger = require('../logger');

async function listCards(userId) {
  const cards = await cardsRepo.listByUserId(userId);
  return { cards };
}

async function getCard(cardId, userId) {
  const card = await cardsRepo.getByIdAndUser(cardId, userId);
  if (!card) {
    throw notFound('CARD_NOT_FOUND', 'Virtual card not found');
  }
  return { card: cardsRepo.formatCard(card) };
}

async function createCard({
  userId,
  accountNumber,
  userName,
  cardType = 'VISA',
  spendingLimit,
  correlationId,
}) {
  const existingCount = await cardsRepo.countByUserId(userId);
  if (existingCount >= config.maxCardsPerUser) {
    throw conflict('CARD_LIMIT_REACHED', `Maximum limit of ${config.maxCardsPerUser} virtual cards reached`);
  }

  const normalizedSpendingLimit = normalizeAmount(
    spendingLimit || config.cardDefaultSpendingLimit,
    'spending_limit'
  );

  const pan = generatePan(cardType);
  const cvv = generateCvv();
  const cvvHash = hashCvv(cvv);
  const maskedPan = maskPan(pan);
  const encryptedPan = encryptPan(pan, config.cardEncryptionKey);

  const now = new Date();
  const expiryMonth = now.getMonth() + 1;
  const expiryYear = now.getFullYear() + config.cardValidityYears;
  const cardHolderName = (userName || 'CARD HOLDER').toUpperCase();

  const row = await cardsRepo.create({
    userId,
    accountNumber,
    cardNumberMasked: maskedPan,
    cardNumberEncrypted: encryptedPan,
    cardHolderName,
    cardType,
    expiryMonth,
    expiryYear,
    cvvHash,
    spendingLimit: normalizedSpendingLimit,
  });

  const formattedCard = cardsRepo.formatCard(row);

  kafkaProducer.sendEvent({
    topic: config.kafka.cardsTopic,
    key: accountNumber,
    eventType: 'CardCreated',
    correlationId,
    data: {
      card_id: formattedCard.card_id,
      account_number: accountNumber,
      card_type: cardType,
      masked: maskedPan,
      balance: '0.00',
      spending_limit: normalizedSpendingLimit,
    },
  });

  // Return formatted card PLUS one-time reveal of clear PAN and CVV
  return {
    card: formattedCard,
    card_number: pan,
    cvv,
  };
}

async function fundCard({
  cardId,
  userId,
  accountNumber,
  amount,
  pin,
  userToken,
  idempotencyKey,
  correlationId,
  traceparent,
  tracestate,
}) {
  const card = await cardsRepo.getByIdAndUser(cardId, userId);
  if (!card) {
    throw notFound('CARD_NOT_FOUND', 'Virtual card not found');
  }

  if (card.is_frozen) {
    throw conflict('CARD_FROZEN', 'Cannot fund a frozen virtual card');
  }

  const normalizedAmount = normalizeAmount(amount);
  const effectiveIdempotencyKey = idempotencyKey || `fund-${cardId}-${Date.now()}`;

  // Call Core Ledger to transfer funds from user account to card pool
  let ledgerData;
  try {
    const res = await httpClient.callHttp({
      method: 'POST',
      url: `${config.ledgerUrl}/api/v1/ledger/transfer`,
      data: {
        idempotency_key: effectiveIdempotencyKey,
        from_account: accountNumber,
        to_account: config.cardsAccountPool,
        amount: normalizedAmount,
        description: 'Virtual Card Funding',
        transaction_type: 'CARD_FUNDING',
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
    ledgerData = res.data;
  } catch (err) {
    if (err.response) {
      const { status, data } = err.response;
      throw new AppError(
        status,
        data?.error || 'LEDGER_ERROR',
        data?.message || 'Card funding failed on ledger',
        data
      );
    }
    throw new AppError(502, 'LEDGER_UNAVAILABLE', 'Ledger service is unavailable');
  }

  // Atomically credit card balance in Postgres
  const updatedRow = await cardsRepo.fundBalance(cardId, normalizedAmount);
  const formattedCard = cardsRepo.formatCard(updatedRow);

  kafkaProducer.sendEvent({
    topic: config.kafka.cardsTopic,
    key: accountNumber,
    eventType: 'CardFunded',
    correlationId,
    data: {
      card_id: cardId,
      account_number: accountNumber,
      card_type: card.card_type,
      masked: card.card_number_masked,
      amount: normalizedAmount,
      balance: formattedCard.balance,
      transaction_ref: ledgerData.transaction_ref,
    },
  });

  return {
    card: formattedCard,
    transaction_ref: ledgerData.transaction_ref,
  };
}

async function withdrawCard({
  cardId,
  userId,
  accountNumber,
  amount,
  pin,
  userToken,
  idempotencyKey,
  correlationId,
  traceparent,
  tracestate,
}) {
  const card = await cardsRepo.getByIdAndUser(cardId, userId);
  if (!card) {
    throw notFound('CARD_NOT_FOUND', 'Virtual card not found');
  }

  if (card.is_frozen) {
    throw conflict('CARD_FROZEN', 'Cannot withdraw from a frozen virtual card');
  }

  const normalizedAmount = normalizeAmount(amount);

  // 1. Verify PIN via Core Ledger
  try {
    await httpClient.callHttp({
      method: 'POST',
      url: `${config.ledgerUrl}/api/v1/accounts/${accountNumber}/verify-pin`,
      data: { pin },
      headers: {
        Authorization: `Bearer ${userToken}`,
      },
      timeout: config.ledgerTimeoutMs,
      correlationId,
      traceparent,
      tracestate,
    });
  } catch (err) {
    if (err.response) {
      const { status, data } = err.response;
      throw new AppError(
        status,
        data?.error || 'INVALID_PIN',
        data?.message || 'PIN verification failed',
        data
      );
    }
    throw new AppError(502, 'LEDGER_UNAVAILABLE', 'Ledger service is unavailable');
  }

  // 2. Atomic balance check & deduction with Postgres row lock
  const client = await db.getClient();
  let updatedRow;
  let ledgerData;

  try {
    await client.query('BEGIN');

    const lockSql = `
      SELECT balance, is_frozen, spending_limit
      FROM virtual_cards
      WHERE card_id = $1
      FOR UPDATE;
    `;
    const lockRes = await client.query(lockSql, [cardId]);
    if (lockRes.rows.length === 0) {
      await client.query('ROLLBACK');
      throw notFound('CARD_NOT_FOUND', 'Virtual card not found');
    }

    const lockedCard = lockRes.rows[0];
    if (lockedCard.is_frozen) {
      await client.query('ROLLBACK');
      throw conflict('CARD_FROZEN', 'Cannot withdraw from a frozen virtual card');
    }

    if (Number(lockedCard.balance) < Number(normalizedAmount)) {
      await client.query('ROLLBACK');
      throw unprocessable('INSUFFICIENT_CARD_BALANCE', 'Insufficient virtual card balance');
    }

    // 3. Call Core Ledger: transfer from card pool back to user account
    const effectiveIdempotencyKey = idempotencyKey || `withdraw-${cardId}-${Date.now()}`;
    try {
      const res = await httpClient.callHttp({
        method: 'POST',
        url: `${config.ledgerUrl}/api/v1/ledger/transfer`,
        data: {
          idempotency_key: effectiveIdempotencyKey,
          from_account: config.cardsAccountPool,
          to_account: accountNumber,
          amount: normalizedAmount,
          description: 'Virtual Card Withdrawal',
          transaction_type: 'CARD_WITHDRAWAL',
        },
        headers: {
          'X-Internal-Token': config.internalToken,
        },
        timeout: config.ledgerTimeoutMs,
        correlationId,
        traceparent,
        tracestate,
      });
      ledgerData = res.data;
    } catch (ledgerErr) {
      await client.query('ROLLBACK');
      if (ledgerErr.response) {
        const { status, data } = ledgerErr.response;
        throw new AppError(
          status,
          data?.error || 'LEDGER_ERROR',
          data?.message || 'Card withdrawal failed on ledger',
          data
        );
      }
      throw new AppError(502, 'LEDGER_UNAVAILABLE', 'Ledger service is unavailable');
    }

    // 4. Update card balance and commit
    const updateSql = `
      UPDATE virtual_cards
      SET balance = balance - $1, updated_at = CURRENT_TIMESTAMP
      WHERE card_id = $2
      RETURNING *;
    `;
    const updateRes = await client.query(updateSql, [normalizedAmount, cardId]);
    updatedRow = updateRes.rows[0];

    await client.query('COMMIT');
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) { /* ignore */ }
    throw err;
  } finally {
    client.release();
  }

  const formattedCard = cardsRepo.formatCard(updatedRow);

  kafkaProducer.sendEvent({
    topic: config.kafka.cardsTopic,
    key: accountNumber,
    eventType: 'CardWithdrawn',
    correlationId,
    data: {
      card_id: cardId,
      account_number: accountNumber,
      card_type: card.card_type,
      masked: card.card_number_masked,
      amount: normalizedAmount,
      balance: formattedCard.balance,
      transaction_ref: ledgerData.transaction_ref,
    },
  });

  return {
    card: formattedCard,
    transaction_ref: ledgerData.transaction_ref,
  };
}

async function updateCardStatus({ cardId, userId, accountNumber, isFrozen, correlationId }) {
  const card = await cardsRepo.getByIdAndUser(cardId, userId);
  if (!card) {
    throw notFound('CARD_NOT_FOUND', 'Virtual card not found');
  }

  const updatedRow = await cardsRepo.updateStatus(cardId, isFrozen);
  const formattedCard = cardsRepo.formatCard(updatedRow);

  kafkaProducer.sendEvent({
    topic: config.kafka.cardsTopic,
    key: accountNumber,
    eventType: 'CardStatusChanged',
    correlationId,
    data: {
      card_id: cardId,
      account_number: accountNumber,
      card_type: card.card_type,
      masked: card.card_number_masked,
      frozen: isFrozen,
    },
  });

  return { card: formattedCard };
}

module.exports = {
  listCards,
  getCard,
  createCard,
  fundCard,
  withdrawCard,
  updateCardStatus,
};
