# ZylkerBank AI & Risk Intelligence Service

Python 3.11 / FastAPI service running on port `8083`. Provides pre-transaction fraud scoring, conversational banking assistant with tool-calling and deterministic fallback, immutable Kafka audit consumer, and simulated transaction notification dispatcher.

## Features

- **Pre-Transaction Risk Engine (`POST /api/v1/risk/evaluate`)**:
  - Velocity checks (≥3 in 60s → +30, ≥6 in 60s → +60).
  - High-amount checks (> $2,000 → +30, > $5,000 → +30 more).
  - First-time beneficiary checks (no prior `TransferCompleted` event → +15).
  - Hour anomaly checks (01:00-04:00 in `RISK_TIMEZONE` with amount > $500 → +25).
  - Decision rules: `score >= 70` → `BLOCKED`, `score >= 30` → `FLAGGED_FOR_REVIEW`, else `APPROVED`.
  - Persists evaluations to PostgreSQL table `risk_evaluations`.

- **Conversational Banking Assistant (`POST /api/v1/chat`, `POST /api/v1/chat/stream`)**:
  - Multi-turn LLM reasoning loop with LiteLLM (max 5 iterations).
  - Tools supported:
    - `get_account_balance`: Interrogates Ledger service (`:8081`).
    - `get_recent_transactions`: Interrogates Ledger statement endpoint (`:8081`).
    - `get_virtual_cards`: Interrogates Financial Gateway (`:8082`).
    - `calculate_transfer_fee`: Calculates fees (P2P free, card funding free, card withdrawal 0.5% capped at $5.00).
  - Deterministic fallback responder when LLM is offline/unreachable (`LLM_FALLBACK_ENABLED=true`).
  - Conversation memory stored in PostgreSQL tables `ai_conversations` and `ai_messages`.
  - Server-Sent Events (SSE) streaming chat endpoint.

- **Kafka Audit Consumer & Alert Dispatcher**:
  - Subscribes to `bank.transfers.v1` and `bank.cards.v1` (`bank-audit-consumers` group).
  - Persists events to immutable `audit_events` table (deduped on `event_id`).
  - Emits simulated debit/credit SMS and Email alerts via dedicated `notifications` logger.

- **Observability & Resilience**:
  - Traceloop OpenLLMetry tracing exported via OTLP (`OTEL_EXPORTER_OTLP_ENDPOINT`).
  - Site24x7 Chaos SDK integration (`site24x7-chaos[fastapi]`).
  - Non-blocking degraded mode: boots and serves `/health` even if Postgres, Kafka, or Ollama are offline.

## Running Locally

```bash
# Activate virtual environment
source .venv/bin/activate

# Run tests
pytest -v

# Run service
uvicorn app.main:app --host 0.0.0.0 --port 8083 --reload
```
