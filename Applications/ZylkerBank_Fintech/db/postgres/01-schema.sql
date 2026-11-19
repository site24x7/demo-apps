-- ─────────────────────────────────────────────────────────────────────────────
-- ZylkerBank — PostgreSQL 16 schema (database: bank_db)
-- Owners: banking-portal (spring_session*), financial-gateway (virtual_cards,
--         payment_requests, idempotency_keys), ai-risk-service (ai_*, audit_events,
--         risk_evaluations). Zero Redis: sessions, chat memory and idempotency
--         all live in PostgreSQL.
-- Customer identity + accounts live in Oracle (BANKLEDGER) — see db/oracle.
-- user_id / account_number columns are loose references (no FK across databases).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Spring Session JDBC (banking-portal) ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS spring_session (
    primary_id            CHAR(36)     NOT NULL,
    session_id            CHAR(36)     NOT NULL,
    creation_time         BIGINT       NOT NULL,
    last_access_time      BIGINT       NOT NULL,
    max_inactive_interval INT          NOT NULL,
    expiry_time           BIGINT       NOT NULL,
    principal_name        VARCHAR(100),
    CONSTRAINT spring_session_pk PRIMARY KEY (primary_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS spring_session_ix1 ON spring_session (session_id);
CREATE INDEX IF NOT EXISTS spring_session_ix2 ON spring_session (expiry_time);
CREATE INDEX IF NOT EXISTS spring_session_ix3 ON spring_session (principal_name);

CREATE TABLE IF NOT EXISTS spring_session_attributes (
    session_primary_id CHAR(36)     NOT NULL,
    attribute_name     VARCHAR(200) NOT NULL,
    attribute_bytes    BYTEA        NOT NULL,
    CONSTRAINT spring_session_attributes_pk PRIMARY KEY (session_primary_id, attribute_name),
    CONSTRAINT spring_session_attributes_fk FOREIGN KEY (session_primary_id)
        REFERENCES spring_session (primary_id) ON DELETE CASCADE
);

-- 2. Virtual cards (financial-gateway) ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS virtual_cards (
    card_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id               VARCHAR(36)   NOT NULL,
    account_number        VARCHAR(30)   NOT NULL,
    card_number_masked    VARCHAR(19)   NOT NULL,          -- '4111 **** **** 1234'
    card_number_encrypted TEXT          NOT NULL,          -- AES-256-GCM (iv:tag:ciphertext, base64)
    card_holder_name      VARCHAR(100)  NOT NULL,
    card_type             VARCHAR(20)   NOT NULL DEFAULT 'VISA',   -- VISA | MASTERCARD
    expiry_month          INT           NOT NULL,
    expiry_year           INT           NOT NULL,
    cvv_hash              VARCHAR(128)  NOT NULL,          -- salt$sha256
    spending_limit        NUMERIC(12,2) NOT NULL DEFAULT 1000.00,   -- daily limit
    balance               NUMERIC(15,2) NOT NULL DEFAULT 0.00,      -- funded card balance
    is_frozen             BOOLEAN       NOT NULL DEFAULT FALSE,
    created_at            TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_virtual_cards_user ON virtual_cards (user_id);
CREATE INDEX IF NOT EXISTS idx_virtual_cards_account ON virtual_cards (account_number);

-- 3. Payment requests (financial-gateway) ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS payment_requests (
    request_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_account VARCHAR(30)   NOT NULL,   -- who asks for money (receives)
    requester_name    VARCHAR(255),
    payer_account     VARCHAR(30)   NOT NULL,   -- who is asked to pay
    payer_name        VARCHAR(255),
    amount            NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    currency          VARCHAR(3)    NOT NULL DEFAULT 'USD',
    description       VARCHAR(255),
    status            VARCHAR(20)   NOT NULL DEFAULT 'REQUEST_SENT'
                      CHECK (status IN ('REQUEST_SENT', 'REQUEST_SETTLED', 'DECLINED')),
    transaction_ref   VARCHAR(36),
    created_at        TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    settled_at        TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_payreq_payer ON payment_requests (payer_account, status);
CREATE INDEX IF NOT EXISTS idx_payreq_requester ON payment_requests (requester_account, status);

-- 4. Idempotency keys (financial-gateway) ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS idempotency_keys (
    idempotency_key  VARCHAR(100) PRIMARY KEY,
    request_hash     VARCHAR(64)  NOT NULL,           -- sha256 of canonical request body + account
    status           VARCHAR(20)  NOT NULL DEFAULT 'IN_PROGRESS',   -- IN_PROGRESS | COMPLETED | FAILED
    response_status  INT,
    response_payload JSONB,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at     TIMESTAMPTZ
);

-- 5. AI chat memory (ai-risk-service) ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_conversations (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id     VARCHAR(100) NOT NULL,
    user_id        VARCHAR(36),
    account_number VARCHAR(12),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_ai_conv_session ON ai_conversations (session_id);

CREATE TABLE IF NOT EXISTS ai_messages (
    id              BIGSERIAL PRIMARY KEY,
    conversation_id UUID        NOT NULL REFERENCES ai_conversations (id) ON DELETE CASCADE,
    role            VARCHAR(20) NOT NULL,             -- user | assistant | tool
    content         TEXT        NOT NULL,
    token_count     INT         NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_ai_msg_conv ON ai_messages (conversation_id, id);

-- 6. Immutable audit log, fed by the Kafka consumer (ai-risk-service) ─────────
CREATE TABLE IF NOT EXISTS audit_events (
    id             BIGSERIAL PRIMARY KEY,
    event_id       VARCHAR(64),                       -- Kafka envelope event_id (dedupe)
    event_type     VARCHAR(50)  NOT NULL,
    topic          VARCHAR(100),
    payload        JSONB        NOT NULL,
    correlation_id VARCHAR(64),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_audit_event_id ON audit_events (event_id) WHERE event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_type ON audit_events (event_type, created_at DESC);

-- Block UPDATE/DELETE on the audit table (immutability)
CREATE OR REPLACE FUNCTION audit_events_immutable() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'audit_events is append-only';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_events_immutable ON audit_events;
CREATE TRIGGER trg_audit_events_immutable
    BEFORE UPDATE OR DELETE ON audit_events
    FOR EACH ROW EXECUTE FUNCTION audit_events_immutable();

-- 7. Risk evaluation history, used for velocity checks (ai-risk-service) ──────
CREATE TABLE IF NOT EXISTS risk_evaluations (
    id             BIGSERIAL PRIMARY KEY,
    from_account   VARCHAR(12)   NOT NULL,
    to_account     VARCHAR(12)   NOT NULL,
    amount         NUMERIC(15,2) NOT NULL,
    risk_score     INT           NOT NULL,
    decision       VARCHAR(24)   NOT NULL,
    reasons        JSONB         NOT NULL DEFAULT '[]'::jsonb,
    correlation_id VARCHAR(64),
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_risk_from_time ON risk_evaluations (from_account, created_at DESC);

-- ── Demo seed: one pre-provisioned virtual card for demo user Alice ──────────
-- (user_id/account match the Oracle seed in db/oracle/01-schema.sql)
-- Card number is a Luhn-valid test PAN (4111 1111 1111 1111); encrypted value is a
-- placeholder that the gateway treats as "not revealable" (reveal returns masked only).
INSERT INTO virtual_cards
    (card_id, user_id, account_number, card_number_masked, card_number_encrypted,
     card_holder_name, card_type, expiry_month, expiry_year, cvv_hash, spending_limit, balance)
VALUES
    ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '2170000001',
     '4111 **** **** 1111', 'SEED', 'ALICE JOHNSON', 'VISA', 12, 2029,
     'seed$0000000000000000000000000000000000000000000000000000000000000000', 2000.00, 250.00)
ON CONFLICT (card_id) DO NOTHING;
