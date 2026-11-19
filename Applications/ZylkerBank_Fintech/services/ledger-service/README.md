# Account & Ledger Service (ZylkerBank)

Core general ledger microservice for ZylkerBank built in Go 1.26 with Gin and pure-Go Oracle driver (`go-ora`).

## Key Responsibilities
- **Double-Entry General Ledger**: Enforces strict financial balancing where every transaction creates equal debit and credit entries (`LEDGER_POSTINGS`).
- **Deadlock-Free Pessimistic Row Locking**: Locks accounts in ascending lexicographical order of `account_id` with `SELECT ... FOR UPDATE` before applying mutations.
- **Idempotency**: Enforces unique `JOURNAL_ENTRIES.idempotency_key` to safely handle client retries and return identical cached receipts (`idempotent_replay: true`).
- **Tier Limits**: Validates daily P2P debit limits per tier (Tier 1: $1,000, Tier 2: $10,000, Tier 3: Unlimited).
- **KYC & Freeze Enforcement**: Blocks transactions if either party is frozen or non-system unverified.
- **PIN Security Engine**: Validates salted PBKDF2 PIN hashes (`120,000` iterations) and enforces a 15-minute lockout after 3 consecutive failures.
- **Statements**: Generates paginated ledger statements with running balance and counterparty resolution.

## Endpoints

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/health` | Public | Service health & Oracle connection status |
| `POST` | `/api/v1/auth/register` | Public | Register customer, allocate account, seed welcome deposit |
| `POST` | `/api/v1/auth/login` | Public | Authenticate with email & password, issue JWT |
| `GET` | `/api/v1/auth/me` | Bearer | Get authenticated user and account profile |
| `POST` | `/api/v1/accounts` | Internal/Bearer | Create new bank account |
| `GET` | `/api/v1/accounts/:n` | Bearer/Internal | Fetch account details by account number |
| `GET` | `/api/v1/accounts/search?q=` | Bearer/Internal | Search accounts by number prefix or user name |
| `POST` | `/api/v1/accounts/:n/verify-pin` | Bearer/Internal | Verify 4-6 digit transaction PIN |
| `POST` | `/api/v1/accounts/:n/kyc` | Internal/Bearer | Update KYC verification and freeze status |
| `POST` | `/api/v1/ledger/transfer` | Bearer/Internal | Execute atomic double-entry balance transfer |
| `GET` | `/api/v1/ledger/statements/:n` | Bearer/Internal | Fetch paginated account statements |

## Environment Defaults (Localhost)

```bash
PORT=8081
ORACLE_HOST=localhost
ORACLE_PORT=1521
ORACLE_SERVICE=FREEPDB1
ORACLE_USER=BANKLEDGER
ORACLE_PASSWORD=ZylkerBank@2024
JWT_SECRET=zylkerbank-dev-jwt-secret-please-change-0123456789
INTERNAL_TOKEN=zylkerbank-internal-dev-token
KYC_AUTO_APPROVE=true
WELCOME_DEPOSIT=1000.00
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_SDK_DISABLED=false
OTEL_SERVICE_NAME=ledger-service
CHAOS_SDK_ENABLED=true
CHAOS_SDK_APP_NAME=ledger-service
```

## Running Tests

```bash
go test -v ./...
```
