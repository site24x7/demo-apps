'use strict';
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const { isValidLuhn, generatePan, luhnCheckDigit } = require('../src/utils/luhn');

describe('Luhn Algorithm & PAN Generation', () => {
  test('isValidLuhn accurately validates valid and invalid credit card numbers', () => {
    // Standard valid Luhn numbers (12-19 digits)
    assert.equal(isValidLuhn('4111111111111111'), true);
    assert.equal(isValidLuhn('4242424242424242'), true);

    // Invalid numbers
    assert.equal(isValidLuhn('4111111111111112'), false);
    assert.equal(isValidLuhn('1234567812345671'), false);
    assert.equal(isValidLuhn(''), false);
    assert.equal(isValidLuhn('abc'), false);
  });

  test('generatePan produces 16-digit Luhn-compliant Visa cards', () => {
    for (let i = 0; i < 20; i++) {
      const pan = generatePan('VISA');
      assert.equal(pan.length, 16, 'PAN must be 16 digits');
      assert.equal(pan.startsWith('4'), true, 'Visa PAN must start with 4');
      assert.equal(isValidLuhn(pan), true, 'Visa PAN must satisfy Luhn check');
    }
  });

  test('generatePan produces 16-digit Luhn-compliant Mastercard cards', () => {
    for (let i = 0; i < 20; i++) {
      const pan = generatePan('MASTERCARD');
      assert.equal(pan.length, 16, 'PAN must be 16 digits');
      const prefix = pan.slice(0, 2);
      assert.match(prefix, /^5[1-5]$/, 'Mastercard PAN must start with 51-55');
      assert.equal(isValidLuhn(pan), true, 'Mastercard PAN must satisfy Luhn check');
    }
  });

  test('luhnCheckDigit calculates the exact digit to satisfy Luhn', () => {
    const partial = '411111111111111'; // 15 digits
    const checkDigit = luhnCheckDigit(partial);
    const fullPan = partial + String(checkDigit);
    assert.equal(isValidLuhn(fullPan), true);
  });
});
