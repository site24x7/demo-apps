'use strict';
const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert/strict');

const cardService = require('../src/services/cardService');
const cardsRepo = require('../src/repositories/cardsRepository');
const kafkaProducer = require('../src/kafka/producer');
const httpClient = require('../src/utils/httpClient');
const db = require('../src/db/pool');

describe('Virtual Card Service', () => {
  let inMemoryCards = new Map();
  let kafkaEvents = [];
  let ledgerTransfers = [];
  let pinVerifications = [];

  beforeEach(() => {
    inMemoryCards.clear();
    kafkaEvents = [];
    ledgerTransfers = [];
    pinVerifications = [];

    // Mock db.query for cards repository and count
    db.query = async (sql, params) => {
      const trimmed = sql.trim();
      if (trimmed.startsWith('SELECT COUNT(*)::int AS count FROM virtual_cards')) {
        const [userId] = params;
        let count = 0;
        for (const card of inMemoryCards.values()) {
          if (card.user_id === userId) count++;
        }
        return { rows: [{ count }] };
      }
      if (trimmed.startsWith('SELECT * FROM virtual_cards WHERE user_id = $1')) {
        const [userId] = params;
        const rows = [];
        for (const card of inMemoryCards.values()) {
          if (card.user_id === userId) rows.push(card);
        }
        return { rows };
      }
      if (trimmed.startsWith('SELECT * FROM virtual_cards WHERE card_id = $1 AND user_id = $2')) {
        const [cardId, userId] = params;
        const card = inMemoryCards.get(cardId);
        if (card && card.user_id === userId) return { rows: [card] };
        return { rows: [] };
      }
      if (trimmed.startsWith('INSERT INTO virtual_cards')) {
        const [
          userId,
          accountNumber,
          cardNumberMasked,
          cardNumberEncrypted,
          cardHolderName,
          cardType,
          expiryMonth,
          expiryYear,
          cvvHash,
          spendingLimit,
        ] = params;
        const cardId = 'card-' + (inMemoryCards.size + 1);
        const card = {
          card_id: cardId,
          user_id: userId,
          account_number: accountNumber,
          card_number_masked: cardNumberMasked,
          card_number_encrypted: cardNumberEncrypted,
          card_holder_name: cardHolderName,
          card_type: cardType,
          expiry_month: expiryMonth,
          expiry_year: expiryYear,
          cvv_hash: cvvHash,
          spending_limit: spendingLimit,
          balance: '0.00',
          is_frozen: false,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        };
        inMemoryCards.set(cardId, card);
        return { rows: [card] };
      }
      if (trimmed.startsWith('UPDATE virtual_cards') && trimmed.includes('SET is_frozen = $1')) {
        const [isFrozen, cardId] = params;
        const card = inMemoryCards.get(cardId);
        if (card) {
          card.is_frozen = isFrozen;
          card.updated_at = new Date().toISOString();
          return { rows: [card] };
        }
        return { rows: [] };
      }
      if (trimmed.startsWith('UPDATE virtual_cards') && trimmed.includes('SET balance = balance + $1')) {
        const [amount, cardId] = params;
        const card = inMemoryCards.get(cardId);
        if (card) {
          card.balance = (Number(card.balance) + Number(amount)).toFixed(2);
          card.updated_at = new Date().toISOString();
          return { rows: [card] };
        }
        return { rows: [] };
      }
      return { rows: [] };
    };

    // Mock db.getClient for transactional withdraw
    db.getClient = async () => {
      return {
        query: async (sql, params) => {
          const trimmed = sql.trim();
          if (trimmed === 'BEGIN' || trimmed === 'COMMIT' || trimmed === 'ROLLBACK') {
            return { rows: [] };
          }
          if (trimmed.includes('FOR UPDATE')) {
            const [cardId] = params;
            const card = inMemoryCards.get(cardId);
            return { rows: card ? [card] : [] };
          }
          if (trimmed.includes('SET balance = balance - $1')) {
            const [amount, cardId] = params;
            const card = inMemoryCards.get(cardId);
            if (card) {
              card.balance = (Number(card.balance) - Number(amount)).toFixed(2);
              card.updated_at = new Date().toISOString();
              return { rows: [card] };
            }
            return { rows: [] };
          }
          return { rows: [] };
        },
        release: () => {},
      };
    };

    // Mock Kafka producer
    kafkaProducer.sendEvent = async (event) => {
      kafkaEvents.push(event);
      return event;
    };

    // Mock HTTP calls
    httpClient.callHttp = async (opts) => {
      if (opts.url.includes('/verify-pin')) {
        pinVerifications.push(opts.data);
        if (opts.data.pin === '0000') {
          const err = new Error('Invalid PIN');
          err.response = { status: 401, data: { error: 'INVALID_PIN', message: 'Invalid PIN' } };
          throw err;
        }
        return { data: { verified: true } };
      }
      if (opts.url.includes('/ledger/transfer')) {
        ledgerTransfers.push(opts.data);
        return {
          data: {
            journal_id: 'jour-card',
            transaction_ref: 'tx-card-' + Date.now(),
            from_balance_after: '5000.00',
            to_balance_after: '1000.00',
          },
        };
      }
      throw new Error(`Unexpected URL ${opts.url}`);
    };
  });

  test('createCard generates new card and one-time plain PAN + CVV', async () => {
    const result = await cardService.createCard({
      userId: 'user-1',
      accountNumber: '2170000001',
      userName: 'Alice Johnson',
      cardType: 'VISA',
      spendingLimit: '1500.00',
    });

    assert.ok(result.card);
    assert.equal(result.card.account_number, '2170000001');
    assert.equal(result.card.card_holder_name, 'ALICE JOHNSON');
    assert.equal(result.card.card_type, 'VISA');
    assert.equal(result.card.spending_limit, '1500.00');
    assert.equal(result.card.balance, '0.00');
    assert.equal(result.card.is_frozen, false);

    // One-time reveal
    assert.ok(result.card_number);
    assert.equal(result.card_number.length, 16);
    assert.equal(result.card_number.startsWith('4'), true);
    assert.ok(result.cvv);
    assert.equal(result.cvv.length, 3);

    // Kafka event
    assert.equal(kafkaEvents.length, 1);
    assert.equal(kafkaEvents[0].eventType, 'CardCreated');
  });

  test('createCard enforces maximum of 5 cards per user', async () => {
    for (let i = 0; i < 5; i++) {
      await cardService.createCard({
        userId: 'user-max',
        accountNumber: '2170000001',
        userName: 'Alice',
      });
    }

    await assert.rejects(
      async () => {
        await cardService.createCard({
          userId: 'user-max',
          accountNumber: '2170000001',
          userName: 'Alice',
        });
      },
      (err) => {
        assert.equal(err.code, 'CARD_LIMIT_REACHED');
        assert.equal(err.status, 409);
        return true;
      }
    );
  });

  test('fundCard tops up virtual card and debits user account via ledger', async () => {
    const created = await cardService.createCard({
      userId: 'user-fund',
      accountNumber: '2170000001',
      userName: 'Alice',
    });

    const fundResult = await cardService.fundCard({
      cardId: created.card.card_id,
      userId: 'user-fund',
      accountNumber: '2170000001',
      amount: '200.00',
      pin: '1234',
      userToken: 'fake-jwt',
    });

    assert.equal(fundResult.card.balance, '200.00');
    assert.ok(fundResult.transaction_ref);
    assert.equal(ledgerTransfers.length, 1);
    assert.equal(ledgerTransfers[0].transaction_type, 'CARD_FUNDING');
    assert.equal(ledgerTransfers[0].to_account, '2170000999');

    // Kafka event
    const fundEvent = kafkaEvents.find((e) => e.eventType === 'CardFunded');
    assert.ok(fundEvent);
    assert.equal(fundEvent.data.amount, '200.00');
  });

  test('fundCard and withdrawCard reject frozen cards with 409 CARD_FROZEN', async () => {
    const created = await cardService.createCard({
      userId: 'user-frozen',
      accountNumber: '2170000001',
      userName: 'Alice',
    });

    await cardService.updateCardStatus({
      cardId: created.card.card_id,
      userId: 'user-frozen',
      accountNumber: '2170000001',
      isFrozen: true,
    });

    await assert.rejects(
      async () => {
        await cardService.fundCard({
          cardId: created.card.card_id,
          userId: 'user-frozen',
          accountNumber: '2170000001',
          amount: '50.00',
          pin: '1234',
        });
      },
      (err) => {
        assert.equal(err.code, 'CARD_FROZEN');
        assert.equal(err.status, 409);
        return true;
      }
    );

    await assert.rejects(
      async () => {
        await cardService.withdrawCard({
          cardId: created.card.card_id,
          userId: 'user-frozen',
          accountNumber: '2170000001',
          amount: '50.00',
          pin: '1234',
        });
      },
      (err) => {
        assert.equal(err.code, 'CARD_FROZEN');
        assert.equal(err.status, 409);
        return true;
      }
    );
  });

  test('withdrawCard checks PIN, checks balance, and executes withdrawal', async () => {
    const created = await cardService.createCard({
      userId: 'user-withdraw',
      accountNumber: '2170000001',
      userName: 'Alice',
    });

    await cardService.fundCard({
      cardId: created.card.card_id,
      userId: 'user-withdraw',
      accountNumber: '2170000001',
      amount: '300.00',
      pin: '1234',
      userToken: 'fake-jwt',
    });

    // Attempt withdraw with invalid PIN -> fails
    await assert.rejects(
      async () => {
        await cardService.withdrawCard({
          cardId: created.card.card_id,
          userId: 'user-withdraw',
          accountNumber: '2170000001',
          amount: '100.00',
          pin: '0000',
          userToken: 'fake-jwt',
        });
      },
      (err) => {
        assert.equal(err.code, 'INVALID_PIN');
        assert.equal(err.status, 401);
        return true;
      }
    );

    // Attempt withdraw exceeding card balance -> 422
    await assert.rejects(
      async () => {
        await cardService.withdrawCard({
          cardId: created.card.card_id,
          userId: 'user-withdraw',
          accountNumber: '2170000001',
          amount: '500.00',
          pin: '1234',
          userToken: 'fake-jwt',
        });
      },
      (err) => {
        assert.equal(err.code, 'INSUFFICIENT_CARD_BALANCE');
        assert.equal(err.status, 422);
        return true;
      }
    );

    // Successful withdraw
    const withdrawResult = await cardService.withdrawCard({
      cardId: created.card.card_id,
      userId: 'user-withdraw',
      accountNumber: '2170000001',
      amount: '100.00',
      pin: '1234',
      userToken: 'fake-jwt',
    });

    assert.equal(withdrawResult.card.balance, '200.00');
    assert.ok(withdrawResult.transaction_ref);

    const withdrawEvent = kafkaEvents.find((e) => e.eventType === 'CardWithdrawn');
    assert.ok(withdrawEvent);
    assert.equal(withdrawEvent.data.amount, '100.00');
    assert.equal(withdrawEvent.data.balance, '200.00');
  });
});
