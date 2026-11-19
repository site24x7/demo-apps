'use strict';
const db = require('../db/pool');
const { fmt } = require('../utils/money');

function formatPaymentRequest(row) {
  if (!row) return null;
  return {
    request_id: row.request_id,
    requester_account: row.requester_account,
    requester_name: row.requester_name,
    payer_account: row.payer_account,
    payer_name: row.payer_name,
    amount: fmt(row.amount),
    currency: row.currency || 'USD',
    description: row.description || '',
    status: row.status,
    transaction_ref: row.transaction_ref || null,
    created_at: row.created_at,
    settled_at: row.settled_at || null,
  };
}

async function create({ requesterAccount, requesterName, payerAccount, payerName, amount, description }) {
  const sql = `
    INSERT INTO payment_requests (
      requester_account, requester_name, payer_account, payer_name,
      amount, currency, description, status
    ) VALUES ($1, $2, $3, $4, $5, 'USD', $6, 'REQUEST_SENT')
    RETURNING *;
  `;
  const res = await db.query(sql, [
    requesterAccount,
    requesterName || null,
    payerAccount,
    payerName || null,
    amount,
    description || null,
  ]);
  return res.rows[0];
}

async function getById(requestId) {
  const sql = `SELECT * FROM payment_requests WHERE request_id = $1;`;
  const res = await db.query(sql, [requestId]);
  return res.rows[0] || null;
}

async function listByUserAccount(accountNumber) {
  const incomingSql = `
    SELECT * FROM payment_requests
    WHERE payer_account = $1
    ORDER BY created_at DESC;
  `;
  const outgoingSql = `
    SELECT * FROM payment_requests
    WHERE requester_account = $1
    ORDER BY created_at DESC;
  `;

  const [incomingRes, outgoingRes] = await Promise.all([
    db.query(incomingSql, [accountNumber]),
    db.query(outgoingSql, [accountNumber]),
  ]);

  return {
    incoming: incomingRes.rows.map(formatPaymentRequest),
    outgoing: outgoingRes.rows.map(formatPaymentRequest),
  };
}

async function settle(requestId, transactionRef) {
  const sql = `
    UPDATE payment_requests
    SET status = 'REQUEST_SETTLED',
        transaction_ref = $2,
        settled_at = CURRENT_TIMESTAMP
    WHERE request_id = $1
    RETURNING *;
  `;
  const res = await db.query(sql, [requestId, transactionRef]);
  return res.rows[0] || null;
}

async function decline(requestId) {
  const sql = `
    UPDATE payment_requests
    SET status = 'DECLINED',
        settled_at = CURRENT_TIMESTAMP
    WHERE request_id = $1
    RETURNING *;
  `;
  const res = await db.query(sql, [requestId]);
  return res.rows[0] || null;
}

module.exports = {
  formatPaymentRequest,
  create,
  getById,
  listByUserAccount,
  settle,
  decline,
};
