# ZylkerBank Financial Gateway Service

The **Financial Gateway** is Service 3 of the ZylkerBank polyglot fintech application. It is implemented in **Node.js 18 / Express** and coordinates peer-to-peer (P2P) transfers, payment requests, and virtual card provisioning/lifecycle management.

## Port & Connectivity
- **HTTP Port**: `8082`
- **Database**: PostgreSQL 16 (`bank_db`, tables: `virtual_cards`, `payment_requests`, `idempotency_keys`)
- **Event Streaming**: Apache Kafka Producer (Topics: `bank.transfers.v1`, `bank.cards.v1`)
- **Internal Dependencies**:
  - AI & Risk Service (`http://localhost:8083`)
  - Account & Ledger Service (`http://localhost:8081`)

## Key Responsibilities
1. **Transfer Orchestrator**:
   - Atomic idempotency checks (`ON CONFLICT DO NOTHING`, replay, in-progress 409, reused key 422, stale recovery).
   - Pre-flight risk evaluation against AI Risk service (2s timeout, **fail-open**).
   - Core Ledger atomic transfer execution (forwards user JWT Bearer token).
   - Best-effort Kafka publishing (`TransferCompleted`).
2. **Payment Requests**:
   - Create payment requests (`REQUEST_SENT`).
   - Categorized incoming and outgoing listing.
   - Payer settlement via orchestrator (`REQUEST_SETTLED`).
   - Decline requests (`DECLINED`).
3. **Virtual Card Engine**:
   - 16-digit Luhn-compliant PAN generation (Visa `4xxx`, Mastercard `51-55xx`).
   - AES-256-GCM encryption of PAN (`CARD_ENCRYPTION_KEY`).
   - Salted SHA-256 CVV hashing and 3-digit CVV generation.
   - PAN masking (`4111 **** **** 1234`).
   - Expiration date calculation (now + 3 years).
   - Max 5 cards per user limit.
   - Freeze / unfreeze toggling (`CARD_FROZEN`).
   - Atomic card funding (`balance += amount`, ledger `CARD_FUNDING`).
   - Atomic card withdrawal with row locks (`balance -= amount`, ledger `CARD_WITHDRAWAL`, PIN verification).
4. **Resilience & Observability**:
   - OpenTelemetry auto-instrumentation & W3C `traceparent` propagation on outbound calls.
   - Correlation ID tracking (`X-Correlation-Id`).
   - Site24x7 Chaos SDK integration.
   - Healthcheck endpoint `/health` (always returns 200, reports dependency status).

## Environment Variables
| Variable | Description | Default |
|---|---|---|
| `PORT` | HTTP Server port | `8082` |
| `DB_HOST` | PostgreSQL host | `localhost` |
| `DB_PORT` | PostgreSQL port | `5432` |
| `DB_NAME` | PostgreSQL database name | `bank_db` |
| `DB_USER` | PostgreSQL user | `postgres` |
| `DB_PASSWORD` | PostgreSQL password | `ZylkerBank@2024` |
| `KAFKA_BROKERS` | Kafka brokers comma-separated | `localhost:9092` |
| `LEDGER_URL` | Core Ledger base URL | `http://localhost:8081` |
| `RISK_URL` | AI Risk service base URL | `http://localhost:8083` |
| `INTERNAL_TOKEN` | Service-to-service internal token | `zylkerbank-internal-dev-token` |
| `JWT_SECRET` | Secret key for HS256 JWT validation | `zylkerbank-dev-jwt-secret-please-change-0123456789` |
| `CARD_ENCRYPTION_KEY` | AES key for virtual card encryption | `zylkerbank-card-encryption-dev-key-change-me` |

## Development & Testing
```bash
# Install dependencies
npm install

# Run static syntax checks
npm run check

# Run unit tests
npm test

# Run service standalone
npm start
# or in development mode (with OTEL disabled)
npm run dev
```
