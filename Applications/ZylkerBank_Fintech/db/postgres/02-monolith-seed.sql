-- ─────────────────────────────────────────────────────────────────────────────
-- Monolith Demo Data Seed for PostgreSQL
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Virtual Cards for Destiny Franks
INSERT INTO virtual_cards (user_id, account_number, card_number_masked, card_number_encrypted, card_holder_name, card_type, expiry_month, expiry_year, cvv_hash, spending_limit, balance)
VALUES 
  ('44444444-1111-4444-1111-111111111111', '2178392293767', '5555 **** **** 7498', 'dummy_enc_pan_7498', 'Destiny Franks', 'MASTERCARD', 12, 2025, 'dummy_cvv_hash', 2500.00, 0.00),
  ('44444444-1111-4444-1111-111111111111', '2178392293767', '4111 **** **** 5675', 'dummy_enc_pan_5675', 'Destiny Franks', 'VISA', 9, 2028, 'dummy_cvv_hash', 2500.00, 0.00),
  ('44444444-1111-4444-1111-111111111111', '2178392293767', '4929 **** **** 3453', 'dummy_enc_pan_3453', 'Lydia Carpenter', 'VISA', 9, 2030, 'dummy_cvv_hash', 2500.00, 0.00)
ON CONFLICT DO NOTHING;

-- 2. Payment Requests
INSERT INTO payment_requests (requester_account, requester_name, payer_account, payer_name, amount, currency, description, status, transaction_ref, settled_at)
VALUES 
  ('2172595575378', 'Gemma Norton', '2178392293767', 'Destiny Franks', 100.00, 'USD', 'New high quality pressing iron', 'REQUEST_SETTLED', 'TRN7FBwCxgLqPAuCEx', '2023-01-16 00:29:11+00'),
  ('2172595575378', 'Gemma Norton', '2178392293767', 'Destiny Franks', 1000.00, 'USD', 'New high quality pressing iron', 'REQUEST_SETTLED', 'TRN4N2xRoihn8igpx5', '2023-01-16 00:59:32+00'),
  ('2172595575378', 'Gemma Norton', '2178392293767', 'Destiny Franks', 500.00, 'USD', 'New high quality pressing iron', 'REQUEST_SETTLED', 'TRN6SnMoHPBNiNwKhP', '2023-01-16 01:01:28+00'),
  ('2172595575378', 'Gemma Norton', '2178392293767', 'Destiny Franks', 655.00, 'USD', 'Settlement for services', 'REQUEST_SETTLED', 'TRN4PgMAqBPJEyg68Q', '2023-01-16 01:06:59+00'),
  ('2171066657962', 'Charles Martin Jr', '2178392293767', 'Destiny Franks', 5000.00, 'USD', 'Payment for the Web Design Job', 'REQUEST_SETTLED', 'TRNAytvPB9GawgiutV', '2023-06-02 10:47:44+00'),
  ('2178392293767', 'Destiny Franks', '2172595575378', 'Gemma Norton', 3000.00, 'USD', 'please can i get this done fast?', 'REQUEST_SENT', 'TRN4hv5wgVBzYeUsgo', NULL)
ON CONFLICT DO NOTHING;
