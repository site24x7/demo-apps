'use strict';
const { badRequest } = require('../errors');

const AMOUNT_RE = /^\d{1,9}(\.\d{1,2})?$/;

/**
 * Parse a decimal string/number input into a canonical 2-decimal string.
 * Rejects zero/negative, >2 decimals, exponent notation, > 999,999,999.99.
 */
function normalizeAmount(input, field = 'amount') {
  if (input === null || input === undefined || typeof input === 'boolean') {
    throw badRequest('INVALID_AMOUNT', `${field} is required`);
  }
  const s = typeof input === 'number' ? String(input) : String(input).trim();
  if (!AMOUNT_RE.test(s)) {
    throw badRequest('INVALID_AMOUNT', `${field} must be a positive decimal with at most 2 fraction digits`);
  }
  const n = Number(s);
  if (!(n > 0)) throw badRequest('INVALID_AMOUNT', `${field} must be greater than zero`);
  return n.toFixed(2);
}

/** Format any numeric-ish value as a string with 2 decimals. */
function fmt(value) {
  if (value === null || value === undefined || value === '') return value;
  const n = Number(value);
  return Number.isFinite(n) ? n.toFixed(2) : String(value);
}

module.exports = { normalizeAmount, fmt, AMOUNT_RE };
