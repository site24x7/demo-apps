# ZylkerBank — Shared Inter-Service Contracts (source of truth)

Overrides the older `zylkerbank_implementation_plan.md` where they differ. The
`zylkerbank_services_blueprint.md` ports/stack/roles are authoritative:

| Svc | Dir | Stack | Port | Datastore |
|---|---|---|---|---|
| Banking Portal / BFF | `services/banking-portal` | Java 17, Spring Boot 3.2.5, Thymeleaf | 8080 | PostgreSQL (`spring_session*`) |
| Account & Ledger | `services/ledger-service` | Go 1.26, Gin, `go-ora` (pure Go, no CGO) | 8081 | Oracle 23c Free, schema `BANKLEDGER` |
| Financial Gateway | `services/financial-gateway` | Node 18, Express, kafkajs, pg | 8082 | PostgreSQL + Kafka producer |
| AI & Risk | `services/ai-risk-service` | Python 3.11, FastAPI, LiteLLM, Traceloop | 8083 | PostgreSQL + Kafka consumer |

Hostnames in docker network: `oracle-db`, `postgres`, `kafka`, `otel-collector`, `ledger-service`,
`financial-gateway`, `ai-risk-service`, `banking-portal`. Every service must also run standalone
on localhost with sensible env defaults (`localhost` hosts) so it can be tested without Docker.

## Conventions (all services)

* JSON, **snake_case** fields. Money = decimal **string or number in, string with 2 decimals out**
  (e.g. `"balance": "8500.00"`). Currency `USD`.
* Error body: `{"error": "UPPER_SNAKE_CODE", "message": "human text"}` + appropriate HTTP status.
* `GET /health` on every service → 200 `{"status":"UP","service":"<name>", ...dependency states}`.
  (Health must return 200 even when optional deps such as Kafka/LLM are degraded; report them in body.)
* **Auth**: Ledger issues JWT (HS256, secret env `JWT_SECRET`, default `zylkerbank-dev-jwt-secret-please-change-0123456789`),
  claims `sub`=user_id, `email`, `name`, `account_number`, `iat`, `exp` (24h). Callers forward
  `Authorization: Bearer <jwt>`. Gateway & AI validate it locally with the same secret.
  Service-to-service calls with no user context (gateway→risk, gateway→ledger for card-pool moves) use
  header `X-Internal-Token: <INTERNAL_TOKEN>` (default `zylkerbank-internal-dev-token`).
* Tracing: every outbound HTTP call propagates W3C `traceparent`/`tracestate`; every inbound is extracted
  (OTel auto instrumentation per stack). `X-Correlation-Id` header optional, echoed in events.
* Chaos SDK (Site24x7) integration per stack, following the **ZylkerKart reference implementation**
  in `../ZylkerKart_Ecommerce/services/` (Java→`product-service`/`storefront`, Go→`search-service`,
  Node→`order-service`, Python→`payment-service`/`ai-assistant`). Same env vars:
  `CHAOS_SDK_ENABLED` (default true), `CHAOS_SDK_APP_NAME`, `CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults`.
  SDK artifacts live in repo-root `chaos-libs/` (`demo-apps/chaos-libs`), referenced via relative path
  from `services/<svc>` = `../../../../chaos-libs/...`, and in Docker via the named build context
  `chaos-libs` (compose `additional_contexts: chaos-libs: ../../chaos-libs`). Dockerfiles must mirror
  repo layout `/repo/Applications/ZylkerBank_Fintech/services/<svc>` exactly like ZylkerKart's Dockerfiles do.
* Seed demo data (Oracle + Postgres) — fixed IDs:

| user | email | password | PIN | user_id | account_number | balance | tier | KYC |
|---|---|---|---|---|---|---|---|---|
| Alice Johnson | alice@zylkerbank.com | `Password@123` | `1234` | `11111111-1111-1111-1111-111111111111` | `2170000001` | 8500.00 | 2 | VERIFIED |
| Bob Smith | bob@zylkerbank.com | `Password@123` | `1234` | `22222222-2222-2222-2222-222222222222` | `2170000002` | 5200.00 | 2 | VERIFIED |
| Charlie Davis | charlie@zylkerbank.com | `Password@123` | `1234` | `33333333-3333-3333-3333-333333333333` | `2170000003` | 1500.00 | 1 | VERIFIED |

  System accounts (user_id `00000000-0000-0000-0000-00000000000X`, no PIN, not searchable, `is_system`):
  `2170000000` ZylkerBank Treasury (balance 1,000,000.00, source of welcome deposits),
  `2170000999` Card Settlement Pool (counter-account for card funding/withdrawal).
  Seeded balances must be backed by balanced journal entries (Treasury → user) so the ledger always
  reconciles: `SUM(CREDIT) - SUM(DEBIT)` per account == balance.
  Postgres seed has Alice card `aaaaaaaa-0000-0000-0000-000000000001` (balance 250.00).

## Service 2 — Ledger (Go, :8081)  `Authorization: Bearer` (own account only) **or** `X-Internal-Token`

Oracle tables (owner `BANKLEDGER`; Ledger owns `db/oracle/01-schema.sql` incl. seed + hashes):
`USERS(user_id, email UNIQUE, password_hash bcrypt cost10, full_name, phone, created_at)`,
`ACCOUNTS(account_id, account_number, user_id, currency, balance, account_status, tier_level, kyc_status,
is_system, created_at)`, `ACCOUNT_SECURITY`, `JOURNAL_ENTRIES`, `LEDGER_POSTINGS` as in the plan DDL.
PIN hash format: `pbkdf2_sha256$<iterations=120000>$<salt_hex>$<hash_hex(32B)>`. 3 failed PINs → lock 15 min.
Tier daily debit limits (P2P_TRANSFER only): T1 1000, T2 10000, T3 unlimited. Account numbers: `217` + 7 digits.

| Method | Path | Request → Response |
|---|---|---|
| POST | `/api/v1/auth/register` | `{email,password,full_name,phone,pin}` → 201 `{token,user:{user_id,email,full_name,phone},account:Account}`; creates account (tier 1, KYC auto-VERIFIED unless `KYC_AUTO_APPROVE=false`), PIN (4–6 digits), and a double-entry welcome deposit (`WELCOME_DEPOSIT`, default 1000.00 from Treasury). 409 `EMAIL_EXISTS` |
| POST | `/api/v1/auth/login` | `{email,password}` → 200 `{token,user,account}`; 401 `INVALID_CREDENTIALS` |
| GET | `/api/v1/auth/me` | Bearer → `{user,account}` |
| POST | `/api/v1/accounts` | internal: `{user_id,initial_deposit?}` → 201 Account |
| GET | `/api/v1/accounts/:n` | → Account |
| GET | `/api/v1/accounts/search?q=` | digits ⇒ prefix match on account_number, else name/email LIKE (case-insens.); max 10; excludes system accounts → `{results:[{account_number,owner_name}]}` |
| POST | `/api/v1/accounts/:n/verify-pin` | `{pin}` → 200 `{verified:true}`; 401 `INVALID_PIN` `{attempts_remaining}`; 423 `PIN_LOCKED` `{locked_until}` |
| POST | `/api/v1/accounts/:n/kyc` | `{status: PENDING_KYC|VERIFIED|REJECTED|FROZEN, document_type?, document_number?}` → Account (FROZEN/REJECTED ⇒ account_status FROZEN) |
| POST | `/api/v1/ledger/transfer` | `{idempotency_key,from_account,to_account,amount,description,transaction_type: P2P_TRANSFER|CARD_FUNDING|CARD_WITHDRAWAL|WELCOME_DEPOSIT,pin?}` → 201 `{journal_id,transaction_ref,transaction_type,from_account,to_account,amount,from_balance_after,to_balance_after,created_at}`; replay of same `idempotency_key` → 200 same body + `idempotent_replay:true`. `pin` required iff `from_account` is not a system account. Locks both rows `SELECT … FOR UPDATE` in ascending account_id order (deadlock-free). Errors: 400 `INVALID_AMOUNT`/`SAME_ACCOUNT`, 401 `INVALID_PIN`, 404 `ACCOUNT_NOT_FOUND`, 403 `ACCOUNT_FROZEN`/`KYC_NOT_VERIFIED`/`DAILY_LIMIT_EXCEEDED`, 422 `INSUFFICIENT_FUNDS`, 423 `PIN_LOCKED` |
| GET | `/api/v1/ledger/statements/:n?page=1&page_size=20&from=&to=` | → `{account_number,page,page_size,total,items:[{posting_id,journal_id,transaction_ref,transaction_type,entry_type,amount,running_balance,description,counterparty_account,counterparty_name,created_at}]}` newest first |

`Account` = `{account_id,account_number,user_id,owner_name,currency,balance,account_status,tier_level,kyc_status,daily_limit,created_at}`.

## Service 3 — Financial Gateway (Node, :8082)  all `/api/v1/*` need `Authorization: Bearer`

Postgres tables per `db/postgres/01-schema.sql` (virtual_cards, payment_requests, idempotency_keys).
Kafka topics `bank.transfers.v1`, `bank.cards.v1` (auto-create; producer `acks=all`, idempotent). Publish is
best-effort: Kafka down must never fail the API call. Event envelope:
`{"event_id":uuid,"event_type":"TransferCompleted|PaymentRequested|PaymentSettled|CardCreated|CardFunded|CardWithdrawn|CardStatusChanged","correlation_id":str,"occurred_at":iso8601,"data":{...}}`, message key = account number.
`TransferCompleted.data` = `{transaction_ref,journal_id,from_account,to_account,from_name,to_name,amount,currency,description,risk_score,risk_decision}`.
Card events carry `{card_id,account_number,card_type,masked,amount?,balance?,frozen?}`.

| Method | Path | Notes |
|---|---|---|
| POST | `/api/v1/transfers/initiate` | header `Idempotency-Key` (required, 400 `IDEMPOTENCY_KEY_REQUIRED`); body `{to_account,amount,description?,pin}`; from = JWT `account_number`. Flow: idempotency (same key+same hash ⇒ stored response + header `Idempotency-Replayed: true`; same key different hash ⇒ 422 `IDEMPOTENCY_KEY_REUSED`; in-flight ⇒ 409 `IDEMPOTENCY_IN_PROGRESS`) → `POST ai-risk /api/v1/risk/evaluate` (2s timeout, **fail-open** if unreachable; `BLOCKED` ⇒ 403 `TRANSFER_BLOCKED` `{risk}`) → ledger transfer (forward user's Bearer) → Kafka `TransferCompleted` → 200 `{status:"COMPLETED",transaction_ref,journal_id,amount,currency,from_account,to_account,recipient_name,description,risk:{score,decision,reasons},new_balance,created_at}`. Ledger errors are passed through with their status/error code. |
| POST | `/api/v1/transfers/requests` | `{payer_account,amount,description?}` → 201 payment request `{request_id,requester_account,requester_name,payer_account,payer_name,amount,description,status,created_at}` |
| GET | `/api/v1/transfers/requests` | → `{incoming:[…as payer],outgoing:[…as requester]}` |
| POST | `/api/v1/transfers/requests/:id/settle` | `{pin}` (+ optional `Idempotency-Key`); caller must be payer & status REQUEST_SENT ⇒ runs orchestrator, status REQUEST_SETTLED, event `PaymentSettled` → request + transfer receipt |
| POST | `/api/v1/transfers/requests/:id/decline` | caller must be payer ⇒ `DECLINED` |
| GET | `/api/v1/cards` | → `{cards:[Card]}` for JWT user |
| POST | `/api/v1/cards` | `{card_type: VISA|MASTERCARD, spending_limit?}` → 201 `Card` + one-time `card_number` (16-digit Luhn; Visa 4…, MC 5…) and `cvv`; max 5 cards/user |
| GET | `/api/v1/cards/:id` | → Card (masked only) |
| POST | `/api/v1/cards/:id/fund` | `{amount,pin}` (+ optional `Idempotency-Key`) → ledger `CARD_FUNDING` (user → `2170000999`, internal-token not needed, forward Bearer) then `balance += amount` → `{card,transaction_ref}`; frozen card ⇒ 409 `CARD_FROZEN` |
| POST | `/api/v1/cards/:id/withdraw` | `{amount,pin}` → card balance check (422 `INSUFFICIENT_CARD_BALANCE`) → ledger `CARD_WITHDRAWAL` (`2170000999` → user, with `X-Internal-Token`) → `balance -= amount`. PIN is verified first via ledger `verify-pin`. |
| PATCH | `/api/v1/cards/:id/status` | `{frozen: bool}` → Card |

`Card` = `{card_id,account_number,card_number_masked,card_holder_name,card_type,expiry_month,expiry_year,spending_limit,balance,is_frozen,created_at}`. Card PAN AES-256-GCM encrypted with env `CARD_ENCRYPTION_KEY`; CVV `salt$sha256`.

## Service 4 — AI & Risk (Python, :8083)

| Method | Path | Notes |
|---|---|---|
| POST | `/api/v1/risk/evaluate` | internal (`X-Internal-Token`, tolerate missing in dev). `{from_account,to_account,amount,timestamp?,correlation_id?}` → `{risk_score:0-100,decision:"APPROVED|FLAGGED_FOR_REVIEW|BLOCKED",reasons:[{rule,points,detail}],evaluated_at}`. Rules (additive): velocity ≥3 evaluations from same account in last 60s +30 (≥6 → +60); amount>2000 +30; amount>5000 +30 more; first-time beneficiary (no prior `TransferCompleted` audit event for the pair) +15; hour anomaly 01:00–04:00 (env `RISK_TIMEZONE`, default UTC) with amount>500 +25. score≥70 BLOCKED, ≥30 FLAGGED_FOR_REVIEW, else APPROVED. Persist to `risk_evaluations`. |
| POST | `/api/v1/chat` | Bearer; `{message,conversation_id?,session_id?}` → `{conversation_id,reply,tool_calls:[{name,arguments,result_summary}],model,usage:{prompt_tokens,completion_tokens}}`. LiteLLM with tool loop (max 5 iterations): `get_account_balance`, `get_recent_transactions` (ledger statement, forward user's Bearer), `get_virtual_cards` (gateway), `calculate_transfer_fee` (local rule: P2P free, card funding free, card withdrawal 0.5% capped at $5.00). Env `LLM_MODEL` (default `ollama/llama3`), `LLM_API_BASE` (default `http://localhost:11434`), `LLM_API_KEY`. If the LLM is unreachable and `LLM_FALLBACK_ENABLED=true` (default) answer with a deterministic keyword-based responder that still calls the same tools, so the demo works without an LLM. History persisted in `ai_conversations`/`ai_messages`. |
| POST | `/api/v1/chat/stream` | same input, SSE (`event: token|tool|done`) |
| GET | `/api/v1/chat/conversations/:id/messages` | Bearer → `{messages:[{role,content,created_at}]}` |
| GET | `/api/v1/audit/logs?event_type=&limit=50&offset=0` | → `{total,items:[{id,event_id,event_type,topic,payload,correlation_id,created_at}]}` |
| GET | `/health` | includes `database`, `kafka`, `llm` states |

Kafka consumer (group `bank-audit-consumers`, topics `bank.transfers.v1`,`bank.cards.v1`, retry subscribe until topics exist, run as background task): insert into `audit_events` (dedupe on `event_id`, `ON CONFLICT DO NOTHING`), and for `TransferCompleted` log simulated SMS (debit to sender / credit to receiver) and Email notifications at INFO via a `notifications` logger. Traceloop OTLP tracing to `OTEL_EXPORTER_OTLP_ENDPOINT` (default `http://otel-collector:4318`, http/protobuf); must be a no-op when `TRACELOOP_ENABLED=false`.

## Service 1 — Banking Portal (Java, :8080)

Env: `LEDGER_URL` (http://localhost:8081), `GATEWAY_URL` (http://localhost:8082), `AI_URL` (http://localhost:8083),
`DB_HOST/DB_PORT/DB_NAME(bank_db)/DB_USER(postgres)/DB_PASSWORD(ZylkerBank@2024)`. The JWT + user/account summary live in the
HTTP session (spring-session-jdbc; table schema pre-created by `db/postgres/01-schema.sql`, so
`spring.session.jdbc.initialize-schema=never` in docker but `embedded`-safe fallback not required).
Outbound calls: `RestTemplate` backed by Apache HttpClient 5 (pooled), traceparent propagated, timeouts, circuit-breaker-ish
error formatting (backend down ⇒ friendly error page, not a stack trace).
Routes: `/` (landing), `/login`, `/register`, `/logout`, `/dashboard`, `/account`, `/transfer/step-1|2|3`, `/transfer/success`,
`/receive/step-1|2|3` (payment requests; also list/settle/decline incoming requests), `/cards` (+`/cards/new`, `/cards/{id}`,
`/cards/{id}/fund|withdraw|freeze|unfreeze`), `/transactions` (statement, paginated), `/api/chat` (JSON proxy to AI `:8083/api/v1/chat`,
session JWT attached), `/api/recipients/search?q=` (proxy to ledger search), `/health` (+`/actuator/health`), 404 page.
Transfer wizard: step-1 pick recipient (search) → step-2 amount/description → step-3 confirm + PIN →
POST generates `Idempotency-Key` UUID (stored in session wizard state at step 2) and calls gateway → success page (receipt).
Templates: port **every** page in `/Users/pazhani-12816/Documents/PM/DEMO/apps/Raw Templates` (Paylio) to Thymeleaf with the
shared `assets/` under `src/main/resources/static/assets`, layout fragments for sidebar/header/footer, real data binding, CSRF-safe forms.
`all-card.html` / `card-detail.html` do **not** exist in Raw Templates — build them in the same Paylio visual style (reuse dashboard card widgets).
Floating AI chat widget (JS + CSS, in layout) on authenticated pages calling `/api/chat`.
