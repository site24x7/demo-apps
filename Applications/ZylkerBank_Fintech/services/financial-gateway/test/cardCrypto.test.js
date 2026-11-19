'use strict';
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const {
  encryptPan,
  decryptPan,
  hashCvv,
  verifyCvv,
  maskPan,
  generateCvv,
} = require('../src/utils/cardCrypto');

const TEST_SECRET = 'super-secret-test-key-32-bytes-long!';

describe('Card Crypto Utilities', () => {
  test('encryptPan and decryptPan perform lossless AES-256-GCM round-trip', () => {
    const pan = '4111222233334444';
    const encrypted = encryptPan(pan, TEST_SECRET);

    assert.notEqual(encrypted, pan);
    assert.equal(encrypted.split(':').length, 3, 'Payload must be iv:tag:ciphertext');

    const decrypted = decryptPan(encrypted, TEST_SECRET);
    assert.equal(decrypted, pan);
  });

  test('decryptPan fails with tampered ciphertext or wrong secret', () => {
    const pan = '4111222233334444';
    const encrypted = encryptPan(pan, TEST_SECRET);

    assert.throws(() => {
      decryptPan(encrypted, 'wrong-secret-key-that-will-fail!!');
    });

    const parts = encrypted.split(':');
    const tampered = `${parts[0]}:${parts[1]}:badciphertext`;
    assert.throws(() => {
      decryptPan(tampered, TEST_SECRET);
    });
  });

  test('hashCvv and verifyCvv correctly check 3-digit CVV', () => {
    const cvv = '789';
    const hash = hashCvv(cvv);

    assert.equal(hash.split('$').length, 2, 'CVV hash format must be salt$digest');
    assert.equal(verifyCvv('789', hash), true);
    assert.equal(verifyCvv('788', hash), false);
    assert.equal(verifyCvv('000', hash), false);
  });

  test('maskPan masks 16-digit card keeping first 4 and last 4', () => {
    const masked = maskPan('4111999988881234');
    assert.equal(masked, '4111 **** **** 1234');
  });

  test('generateCvv generates a 3-digit numeric string', () => {
    for (let i = 0; i < 20; i++) {
      const cvv = generateCvv();
      assert.match(cvv, /^\d{3}$/, 'CVV must be 3 digits');
    }
  });
});
