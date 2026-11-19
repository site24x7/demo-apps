-- ─────────────────────────────────────────────────────────────────────────────
-- ZylkerBank — Oracle Database 23c Free schema (schema: BANKLEDGER)
-- Owner: ledger-service (Go 1.26 / Gin)
-- Authoritative general ledger: USERS, ACCOUNTS, ACCOUNT_SECURITY,
-- JOURNAL_ENTRIES, LEDGER_POSTINGS.
-- All transactions are double-entry with debit == credit per journal entry.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = BANKLEDGER;

-- 1. USERS Table ───────────────────────────────────────────────────────────────
CREATE TABLE users (
    user_id         VARCHAR2(36) PRIMARY KEY,
    email           VARCHAR2(255) UNIQUE NOT NULL,
    password_hash   VARCHAR2(100) NOT NULL,
    full_name       VARCHAR2(255) NOT NULL,
    phone           VARCHAR2(50),
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 2. ACCOUNTS Table ────────────────────────────────────────────────────────────
CREATE TABLE accounts (
    account_id      VARCHAR2(36) PRIMARY KEY,
    account_number  VARCHAR2(30) UNIQUE NOT NULL,
    user_id         VARCHAR2(36) NOT NULL,
    currency        VARCHAR2(3) DEFAULT 'USD' NOT NULL,
    balance         NUMBER(15, 2) DEFAULT 0.00 NOT NULL,
    account_status  VARCHAR2(20) DEFAULT 'ACTIVE' NOT NULL
                    CHECK (account_status IN ('ACTIVE', 'FROZEN', 'CLOSED')),
    tier_level      NUMBER(1) DEFAULT 1 NOT NULL,
    kyc_status      VARCHAR2(20) DEFAULT 'VERIFIED' NOT NULL
                    CHECK (kyc_status IN ('PENDING_KYC', 'VERIFIED', 'REJECTED', 'FROZEN')),
    is_system       NUMBER(1) DEFAULT 0 NOT NULL CHECK (is_system IN (0, 1)),
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_accounts_user FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- 3. ACCOUNT_SECURITY Table (PIN & Lockout) ────────────────────────────────────
CREATE TABLE account_security (
    account_id      VARCHAR2(36) PRIMARY KEY,
    pin_hash        VARCHAR2(255) NOT NULL,
    failed_attempts NUMBER(2) DEFAULT 0 NOT NULL,
    locked_until    TIMESTAMP WITH TIME ZONE NULL,
    CONSTRAINT fk_sec_account FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
);

-- 4. JOURNAL_ENTRIES Table (Master Transactions) ──────────────────────────────
CREATE TABLE journal_entries (
    journal_id       VARCHAR2(36) PRIMARY KEY,
    transaction_ref  VARCHAR2(36) UNIQUE NOT NULL,
    idempotency_key  VARCHAR2(64) UNIQUE NOT NULL,
    transaction_type VARCHAR2(30) NOT NULL,
    description      VARCHAR2(255),
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 5. LEDGER_POSTINGS Table (Debits = Credits) ──────────────────────────────────
CREATE TABLE ledger_postings (
    posting_id      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    journal_id      VARCHAR2(36) NOT NULL,
    account_id      VARCHAR2(36) NOT NULL,
    entry_type      VARCHAR2(6) NOT NULL CHECK (entry_type IN ('DEBIT', 'CREDIT')),
    amount          NUMBER(15, 2) NOT NULL CHECK (amount > 0),
    running_balance NUMBER(15, 2) NOT NULL,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_postings_journal FOREIGN KEY (journal_id) REFERENCES journal_entries(journal_id),
    CONSTRAINT fk_postings_account FOREIGN KEY (account_id) REFERENCES accounts(account_id)
);

-- Indexes ──────────────────────────────────────────────────────────────────────
CREATE INDEX idx_postings_account ON ledger_postings(account_id, created_at DESC);
CREATE INDEX idx_postings_journal ON ledger_postings(journal_id);
CREATE INDEX idx_accounts_user ON accounts(user_id);
CREATE INDEX idx_journal_type_time ON journal_entries(transaction_type, created_at);

-- ── DEMO SEED DATA ────────────────────────────────────────────────────────────

-- System Users
INSERT INTO users (user_id, email, password_hash, full_name, phone)
VALUES ('00000000-0000-0000-0000-000000000000', 'reserve@zylkerbank.internal', 'SYSTEM_ACCOUNT_NO_LOGIN', 'Zylker Central Reserve', '+1-800-ZYLKER');

INSERT INTO users (user_id, email, password_hash, full_name, phone)
VALUES ('00000000-0000-0000-0000-000000000001', 'treasury@zylkerbank.internal', 'SYSTEM_ACCOUNT_NO_LOGIN', 'ZylkerBank Treasury', '+1-800-ZYLKER');

INSERT INTO users (user_id, email, password_hash, full_name, phone)
VALUES ('00000000-0000-0000-0000-000000000002', 'cardspool@zylkerbank.internal', 'SYSTEM_ACCOUNT_NO_LOGIN', 'Card Settlement Pool', '+1-800-ZYLKER');

-- Demo Customers (Password@123 hashed with bcrypt cost 10)
INSERT INTO users (user_id, email, password_hash, full_name, phone)
VALUES ('11111111-1111-1111-1111-111111111111', 'alice@zylkerbank.com', '$2a$10$O5EJ9CVnCj6lM9LwYzZ3x.2TVEX.XmUX9scWwWQmJAsbguqtYByDy', 'Alice Johnson', '+1-555-0101');

INSERT INTO users (user_id, email, password_hash, full_name, phone)
VALUES ('22222222-2222-2222-2222-222222222222', 'bob@zylkerbank.com', '$2a$10$O5EJ9CVnCj6lM9LwYzZ3x.2TVEX.XmUX9scWwWQmJAsbguqtYByDy', 'Bob Smith', '+1-555-0102');

INSERT INTO users (user_id, email, password_hash, full_name, phone)
VALUES ('33333333-3333-3333-3333-333333333333', 'charlie@zylkerbank.com', '$2a$10$O5EJ9CVnCj6lM9LwYzZ3x.2TVEX.XmUX9scWwWQmJAsbguqtYByDy', 'Charlie Davis', '+1-555-0103');

-- Accounts
-- System Accounts
INSERT INTO accounts (account_id, account_number, user_id, currency, balance, account_status, tier_level, kyc_status, is_system)
VALUES ('00000000-0000-0000-0000-000000000000', '2170000008', '00000000-0000-0000-0000-000000000000', 'USD', -1015200.00, 'ACTIVE', 3, 'VERIFIED', 1);

INSERT INTO accounts (account_id, account_number, user_id, currency, balance, account_status, tier_level, kyc_status, is_system)
VALUES ('00000000-0000-0000-0000-000000000001', '2170000000', '00000000-0000-0000-0000-000000000001', 'USD', 1000000.00, 'ACTIVE', 3, 'VERIFIED', 1);

INSERT INTO accounts (account_id, account_number, user_id, currency, balance, account_status, tier_level, kyc_status, is_system)
VALUES ('00000000-0000-0000-0000-000000000002', '2170000999', '00000000-0000-0000-0000-000000000002', 'USD', 0.00, 'ACTIVE', 3, 'VERIFIED', 1);

-- Customer Accounts
INSERT INTO accounts (account_id, account_number, user_id, currency, balance, account_status, tier_level, kyc_status, is_system)
VALUES ('11111111-0000-0000-0000-000000000001', '2170000001', '11111111-1111-1111-1111-111111111111', 'USD', 8500.00, 'ACTIVE', 2, 'VERIFIED', 0);

INSERT INTO accounts (account_id, account_number, user_id, currency, balance, account_status, tier_level, kyc_status, is_system)
VALUES ('22222222-0000-0000-0000-000000000002', '2170000002', '22222222-2222-2222-2222-222222222222', 'USD', 5200.00, 'ACTIVE', 2, 'VERIFIED', 0);

INSERT INTO accounts (account_id, account_number, user_id, currency, balance, account_status, tier_level, kyc_status, is_system)
VALUES ('33333333-0000-0000-0000-000000000003', '2170000003', '33333333-3333-3333-3333-333333333333', 'USD', 1500.00, 'ACTIVE', 1, 'VERIFIED', 0);

-- Customer Security PINs (PBKDF2 sha256 120,000 iterations for PIN '1234')
INSERT INTO account_security (account_id, pin_hash, failed_attempts, locked_until)
VALUES ('11111111-0000-0000-0000-000000000001', 'pbkdf2_sha256$120000$c9bc6cafe7781694f8b33d82cc8cbce6$2cb75893add569c550ee7c034239e35749d04923078fda5df03786c5414d0a6f', 0, NULL);

INSERT INTO account_security (account_id, pin_hash, failed_attempts, locked_until)
VALUES ('22222222-0000-0000-0000-000000000002', 'pbkdf2_sha256$120000$1468a17d3a9e652cc0da48ac14b4c90d$49d6fa39e7d23d1953235c0dc5aab563aad82cb49fed857247f1e1a4a2b0a6a3', 0, NULL);

INSERT INTO account_security (account_id, pin_hash, failed_attempts, locked_until)
VALUES ('33333333-0000-0000-0000-000000000003', 'pbkdf2_sha256$120000$d58d46372e0b5660b7a2b62524f13fca$01bd85b27bebab8a6c3953b36c67338a02e481c6bbad62810fa5797e4b7e079d', 0, NULL);

-- Balanced Journal Entries Backing Seed Balances (Debits == Credits)

-- J0: Initial Capital to Treasury from Reserve ($1,015,200.00)
INSERT INTO journal_entries (journal_id, transaction_ref, idempotency_key, transaction_type, description)
VALUES ('00000000-0000-0000-0000-000000000001', 'TRN-INIT-CAPITAL-0001', 'INIT-CAPITAL-TREASURY', 'CAPITAL_INJECTION', 'Initial capital funding for ZylkerBank Treasury');

INSERT INTO ledger_postings (journal_id, account_id, entry_type, amount, running_balance)
VALUES ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'DEBIT', 1015200.00, -1015200.00);

INSERT INTO ledger_postings (journal_id, account_id, entry_type, amount, running_balance)
VALUES ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'CREDIT', 1015200.00, 1015200.00);

-- J1: Seed deposit to Alice ($8,500.00)
INSERT INTO journal_entries (journal_id, transaction_ref, idempotency_key, transaction_type, description)
VALUES ('00000000-0000-0000-0000-000000000002', 'TRN-SEED-ALICE-0001', 'SEED-DEPOSIT-ALICE', 'WELCOME_DEPOSIT', 'Initial demo balance deposit from Treasury');

INSERT INTO ledger_postings (journal_id, account_id, entry_type, amount, running_balance)
VALUES ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'DEBIT', 8500.00, 1006700.00);

INSERT INTO ledger_postings (journal_id, account_id, entry_type, amount, running_balance)
VALUES ('00000000-0000-0000-0000-000000000002', '11111111-0000-0000-0000-000000000001', 'CREDIT', 8500.00, 8500.00);

-- J2: Seed deposit to Bob ($5,200.00)
INSERT INTO journal_entries (journal_id, transaction_ref, idempotency_key, transaction_type, description)
VALUES ('00000000-0000-0000-0000-000000000003', 'TRN-SEED-BOB-0001', 'SEED-DEPOSIT-BOB', 'WELCOME_DEPOSIT', 'Initial demo balance deposit from Treasury');

INSERT INTO ledger_postings (journal_id, account_id, entry_type, amount, running_balance)
VALUES ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'DEBIT', 5200.00, 1001500.00);

INSERT INTO ledger_postings (journal_id, account_id, entry_type, amount, running_balance)
VALUES ('00000000-0000-0000-0000-000000000003', '22222222-0000-0000-0000-000000000002', 'CREDIT', 5200.00, 5200.00);

-- J3: Seed deposit to Charlie ($1,500.00)
INSERT INTO journal_entries (journal_id, transaction_ref, idempotency_key, transaction_type, description)
VALUES ('00000000-0000-0000-0000-000000000004', 'TRN-SEED-CHARLIE-0001', 'SEED-DEPOSIT-CHARLIE', 'WELCOME_DEPOSIT', 'Initial demo balance deposit from Treasury');

INSERT INTO ledger_postings (journal_id, account_id, entry_type, amount, running_balance)
VALUES ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', 'DEBIT', 1500.00, 1000000.00);

INSERT INTO ledger_postings (journal_id, account_id, entry_type, amount, running_balance)
VALUES ('00000000-0000-0000-0000-000000000004', '33333333-0000-0000-0000-000000000003', 'CREDIT', 1500.00, 1500.00);

COMMIT;
