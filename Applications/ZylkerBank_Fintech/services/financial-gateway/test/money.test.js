'use strict';
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const { normalizeAmount, fmt } = require('../src/utils/money');

describe('Money Utilities', () => {
  test('normalizeAmount parses string and number into 2-decimal string', () => {
    assert.equal(normalizeAmount('100'), '100.00');
    assert.equal(normalizeAmount(100), '100.00');
    assert.equal(normalizeAmount('49.9'), '49.90');
    assert.equal(normalizeAmount('250.75'), '250.75');
    assert.equal(normalizeAmount(12.34), '12.34');
  });

  test('normalizeAmount rejects invalid, zero, or negative amounts', () => {
    const isInvalid = (err) => err.code === 'INVALID_AMOUNT';
    assert.throws(() => normalizeAmount('0'), isInvalid);
    assert.throws(() => normalizeAmount(0), isInvalid);
    assert.throws(() => normalizeAmount('-50'), isInvalid);
    assert.throws(() => normalizeAmount('10.999'), isInvalid);
    assert.throws(() => normalizeAmount('abc'), isInvalid);
    assert.throws(() => normalizeAmount(null), isInvalid);
    assert.throws(() => normalizeAmount(undefined), isInvalid);
    assert.throws(() => normalizeAmount(false), isInvalid);
  });

  test('fmt converts numeric values to 2-decimal strings', () => {
    assert.equal(fmt(8500), '8500.00');
    assert.equal(fmt('5200.5'), '5200.50');
    assert.equal(fmt(null), null);
    assert.equal(fmt(undefined), undefined);
  });
});
