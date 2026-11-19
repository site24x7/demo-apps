'use strict';
const crypto = require('crypto');

/** Check digit that makes `partial + digit` pass the Luhn check. */
function luhnCheckDigit(partial) {
  let sum = 0;
  let double = true; // rightmost digit of the partial becomes 2nd from right once the check digit is appended
  for (let i = partial.length - 1; i >= 0; i--) {
    let d = partial.charCodeAt(i) - 48;
    if (double) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    double = !double;
  }
  return (10 - (sum % 10)) % 10;
}

function isValidLuhn(pan) {
  if (!/^\d{12,19}$/.test(pan)) return false;
  let sum = 0;
  let double = false;
  for (let i = pan.length - 1; i >= 0; i--) {
    let d = pan.charCodeAt(i) - 48;
    if (double) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    double = !double;
  }
  return sum % 10 === 0;
}

/** Generate a 16-digit Luhn-valid PAN. VISA => 4xxx..., MASTERCARD => 51-55xx... */
function generatePan(cardType) {
  let prefix;
  if (cardType === 'MASTERCARD') prefix = '5' + String(crypto.randomInt(1, 6));
  else prefix = '4';
  let body = prefix;
  while (body.length < 15) body += String(crypto.randomInt(0, 10));
  return body + String(luhnCheckDigit(body));
}

module.exports = { luhnCheckDigit, isValidLuhn, generatePan };
