'use strict';
const db = require('../db/pool');
const { fmt } = require('../utils/money');

function formatCard(row) {
  if (!row) return null;
  return {
    card_id: row.card_id,
    account_number: row.account_number,
    card_number_masked: row.card_number_masked,
    card_holder_name: row.card_holder_name,
    card_type: row.card_type,
    expiry_month: Number(row.expiry_month),
    expiry_year: Number(row.expiry_year),
    spending_limit: fmt(row.spending_limit),
    balance: fmt(row.balance),
    is_frozen: Boolean(row.is_frozen),
    created_at: row.created_at,
  };
}

async function countByUserId(userId) {
  const sql = `SELECT COUNT(*)::int AS count FROM virtual_cards WHERE user_id = $1;`;
  const res = await db.query(sql, [userId]);
  return res.rows[0]?.count || 0;
}

async function listByUserId(userId) {
  const sql = `SELECT * FROM virtual_cards WHERE user_id = $1 ORDER BY created_at DESC;`;
  const res = await db.query(sql, [userId]);
  return res.rows.map(formatCard);
}

async function getByIdAndUser(cardId, userId) {
  const sql = `SELECT * FROM virtual_cards WHERE card_id = $1 AND user_id = $2;`;
  const res = await db.query(sql, [cardId, userId]);
  return res.rows[0] || null;
}

async function create({
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
}) {
  const sql = `
    INSERT INTO virtual_cards (
      user_id, account_number, card_number_masked, card_number_encrypted,
      card_holder_name, card_type, expiry_month, expiry_year, cvv_hash,
      spending_limit, balance, is_frozen
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 0.00, FALSE)
    RETURNING *;
  `;
  const res = await db.query(sql, [
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
  ]);
  return res.rows[0];
}

async function updateStatus(cardId, isFrozen) {
  const sql = `
    UPDATE virtual_cards
    SET is_frozen = $1, updated_at = CURRENT_TIMESTAMP
    WHERE card_id = $2
    RETURNING *;
  `;
  const res = await db.query(sql, [isFrozen, cardId]);
  return res.rows[0] || null;
}

async function fundBalance(cardId, amount) {
  const sql = `
    UPDATE virtual_cards
    SET balance = balance + $1, updated_at = CURRENT_TIMESTAMP
    WHERE card_id = $2
    RETURNING *;
  `;
  const res = await db.query(sql, [amount, cardId]);
  return res.rows[0] || null;
}

module.exports = {
  formatCard,
  countByUserId,
  listByUserId,
  getByIdAndUser,
  create,
  updateStatus,
  fundBalance,
};
