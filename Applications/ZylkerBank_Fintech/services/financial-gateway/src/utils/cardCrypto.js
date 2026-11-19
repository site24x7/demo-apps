'use strict';
const crypto = require('crypto');

/** Derive a 32-byte AES key from the configured secret (64-hex, 44-char base64, or any passphrase). */
function deriveKey(secret) {
  if (/^[0-9a-fA-F]{64}$/.test(secret)) return Buffer.from(secret, 'hex');
  if (/^[A-Za-z0-9+/]{43}=$/.test(secret)) return Buffer.from(secret, 'base64');
  return crypto.createHash('sha256').update(String(secret), 'utf8').digest();
}

/** AES-256-GCM. Output format: base64(iv):base64(tag):base64(ciphertext) */
function encryptPan(pan, secret) {
  const key = deriveKey(secret);
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ct = Buffer.concat([cipher.update(String(pan), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [iv, tag, ct].map((b) => b.toString('base64')).join(':');
}

function decryptPan(payload, secret) {
  const [iv, tag, ct] = String(payload).split(':').map((p) => Buffer.from(p, 'base64'));
  if (!iv || !tag || !ct) throw new Error('Malformed encrypted PAN');
  const decipher = crypto.createDecipheriv('aes-256-gcm', deriveKey(secret), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ct), decipher.final()]).toString('utf8');
}

/** CVV is never stored in clear: `salt$sha256hex(salt + cvv)`. */
function hashCvv(cvv, salt = crypto.randomBytes(16).toString('hex')) {
  const digest = crypto.createHash('sha256').update(salt + String(cvv), 'utf8').digest('hex');
  return `${salt}$${digest}`;
}

function verifyCvv(cvv, stored) {
  const [salt] = String(stored).split('$');
  const expected = Buffer.from(hashCvv(cvv, salt));
  const actual = Buffer.from(String(stored));
  return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
}

/** `4111 **** **** 1234` */
function maskPan(pan) {
  const p = String(pan).replace(/\D/g, '');
  return `${p.slice(0, 4)} **** **** ${p.slice(-4)}`;
}

function generateCvv() {
  return String(crypto.randomInt(0, 1000)).padStart(3, '0');
}

module.exports = { deriveKey, encryptPan, decryptPan, hashCvv, verifyCvv, maskPan, generateCvv };
