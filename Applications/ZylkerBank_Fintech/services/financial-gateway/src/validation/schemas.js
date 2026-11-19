'use strict';
const { z } = require('zod');
const { AMOUNT_RE } = require('../utils/money');

const amountSchema = z.union([z.string(), z.number()])
  .refine((v) => {
    const s = String(v).trim();
    if (!AMOUNT_RE.test(s)) return false;
    const n = Number(s);
    return n > 0;
  }, { message: 'Must be a positive decimal with at most 2 fraction digits' });

const pinSchema = z.union([z.string(), z.number()])
  .transform(String)
  .refine((s) => /^\d{4,6}$/.test(s), { message: 'PIN must be 4 to 6 digits' });

const initiateTransferSchema = z.object({
  to_account: z.string().min(1, 'to_account is required').trim(),
  amount: amountSchema,
  description: z.string().max(255).optional(),
  pin: pinSchema,
});

const createPaymentRequestSchema = z.object({
  payer_account: z.string().min(1, 'payer_account is required').trim(),
  amount: amountSchema,
  description: z.string().max(255).optional(),
});

const settlePaymentRequestSchema = z.object({
  pin: pinSchema,
});

const createCardSchema = z.object({
  card_type: z.enum(['VISA', 'MASTERCARD']).optional().default('VISA'),
  spending_limit: amountSchema.optional(),
});

const cardFundWithdrawSchema = z.object({
  amount: amountSchema,
  pin: pinSchema,
});

const cardStatusSchema = z.object({
  frozen: z.boolean().optional(),
  is_frozen: z.boolean().optional(),
}).refine((data) => typeof data.frozen === 'boolean' || typeof data.is_frozen === 'boolean', {
  message: 'Either frozen or is_frozen boolean must be provided',
});

module.exports = {
  initiateTransferSchema,
  createPaymentRequestSchema,
  settlePaymentRequestSchema,
  createCardSchema,
  cardFundWithdrawSchema,
  cardStatusSchema,
};
