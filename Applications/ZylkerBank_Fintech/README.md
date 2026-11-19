# 🏦 ZylkerBank — Polyglot Microservices Financial Platform

ZylkerBank is an enterprise-grade digital banking and fintech demonstration platform built with **5 microservices across 4 programming languages**, dual database engines (**Oracle Database 23c Free** and **PostgreSQL 16**), event-driven messaging with **Apache Kafka**, and unified edge routing through an asynchronous **Python API Gateway**.

The platform is purpose-built for demonstrating **modern polyglot architectures**, **distributed consistency**, and **resilience & showcase observability capabilities of Site24x7**.

---

## 📋 Table of Contents

- [Application Overview](#-application-overview)
- [Architecture Diagram](#-architecture-diagram)
- [Microservices & Tech Stack](#-microservices--tech-stack)
- [API Gateway Routing](#-api-gateway-routing)
- [Database & Event Architecture](#-database--event-architecture)
- [Site24x7 Chaos SDK Integration](#-site24x7-chaos-sdk-integration)
  - [Supported Fault Types](#supported-fault-types)
  - [Configuration & Runtime](#configuration--runtime)
- [Site24x7 APM Insight Integration](#-site24x7-apm-insight-integration)
  - [Zero-Code Agent Injection](#zero-code-agent-injection)
  - [Enabling APM Monitoring](#enabling-apm-monitoring)
- [Demo Credentials](#-demo-credentials)
- [Deployment & Quick Start](#-deployment--quick-start)
  - [Docker Compose](#docker-compose)
  - [Kubernetes (k8s)](#kubernetes-k8s)
- [Health & Verification Endpoints](#-health--verification-endpoints)
- [Backend API Contracts](#-backend-api-contracts)

---

## 🏗 Application Overview

ZylkerBank delivers an authentic online banking experience replicating enterprise retail banking workflows:
- **API Gateway (Edge Router)**: Unified public entrypoint, route multiplexing, correlation tracking, and edge fault injection.
- **Banking Portal & BFF**: Server-side rendered responsive web UI (Thymeleaf), session management, and backend aggregation.
- **Double-Entry Ledger**: Immutable financial accounting, balanced credit/debit journals, ACID transaction posting in Oracle 23c.
- **Financial Gateway**: Transfer orchestration, recipient validation, payment requests, and virtual card issuance with AES-256 encryption.
- **AI & Risk Intelligence**: Pre-transaction fraud scoring, audit trail consumption over Kafka, and conversational banking assistant.

---

## 🏛 Architecture Diagram

```
                                  CLIENTS / BROWSERS
                         (Web Application, Mobile, 3rd Party APIs)
                                        │
                                        │ HTTP / Port 8000
                                        ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        API GATEWAY (Python 3.11 / FastAPI / HTTPX)                     │
│                                       Port: 8000                                       │
│       • Edge Routing  • Correlation ID Tracking  • Site24x7 Python Chaos SDK           │
└───────┬────────────────────────────┬────────────────────────────┬──────────────────────┘
        │                            │                            │
        │ Web & BFF Traffic          │ /api/v1/ledger/**          │ /api/v1/transfers/**
        │ /**                        │ /api/v1/accounts/**        │ /api/v1/cards/**
        ▼                            ▼                            ▼
┌────────────────────────────┐ ┌───────────────────────────┐ ┌───────────────────────────┐
│   Banking Portal & BFF     │ │ Account & Ledger Service  │ │ Financial Gateway Service │
│                            │ │                           │ │                           │
│     Java 17 (Spring Boot)  │ │          Go 1.26          │ │        Node.js 18         │
│          Port: 8080        │ │        Port: 8081         │ │        Port: 8082         │
└─────────────┬──────────────┘ └─────────────┬─────────────┘ └─────────────┬─────────────┘
              │                              │                             │
              │                              │                             │ /api/v1/risk/**
              │                              │                             │ /api/v1/chat/**
              │                              │                             ▼
              │                              │               ┌───────────────────────────┐
              │                              │               │   AI & Risk Intelligence  │
              │                              │               │   Python 3.11 (FastAPI)   │
              │                              │               │        Port: 8083         │
              │                              │               └─────────────┬─────────────┘
              ▼                              ▼                             ▼
┌────────────────────────────┐ ┌───────────────────────────┐ ┌───────────────────────────┐
│       PostgreSQL 16        │ │ Oracle Database 23c Free  │ │    Apache Kafka (KRaft)   │
│         Port: 5432         │ │        Port: 1521         │ │        Port: 9092         │
│     Database: bank_db      │ │    Schema: BANKLEDGER     │ │ Topics: bank.transfers.v1 │
│(Sessions, Cards, Transfers)│ │ (Users, Accounts, Ledgers)│ │         bank.cards.v1     │
└────────────────────────────┘ └───────────────────────────┘ └───────────────────────────┘
```

---

## 🔧 Microservices & Tech Stack

| Service | Language / Runtime | Framework | Port | Primary Datastore | Key Responsibilities |
|---|---|---|---|---|---|
| **API Gateway** | Python 3.11 | FastAPI, Uvicorn, HTTPX | `8000` | In-memory / Downstream | Unified edge ingress, route proxying, correlation tracking, chaos edge injection |
| **Banking Portal** | Java 17 (Temurin) | Spring Boot 3.2.5, Thymeleaf | `8080` | PostgreSQL (`spring_session`) | SSR UI, user authentication flow, BFF aggregation, static asset delivery |
| **Ledger Service** | Go 1.26 | Gin Web Framework, `go-ora` | `8081` | Oracle 23c Free (`BANKLEDGER`) | High-integrity double-entry journal postings, balance checks, KYC, PIN verification |
| **Financial Gateway** | Node.js 18 | Express, `pg`, `kafkajs` | `8082` | PostgreSQL 16 (`bank_db`) | Transfer lifecycle, payment requests, virtual card creation & AES encryption, Kafka producer |
| **AI & Risk Service** | Python 3.11 | FastAPI, Uvicorn, asyncpg | `8083` | PostgreSQL 16 (`bank_db`) | Real-time transfer fraud evaluation, async Kafka event auditing, conversational AI |

---

## 🔀 API Gateway Routing

All external clients connect through the single public entrypoint on port `8000`:

| Ingress Route Pattern | Target Destination | Handling Service | Description |
|---|---|---|---|
| `/api/v1/ledger/**`<br>`/api/v1/accounts/**`<br>`/api/v1/auth/**`<br>`/api/v1/users/**` | `http://ledger-service:8081` | **Ledger Service** (Go) | User profiles, account balance checks, JWT auth, transaction PIN security |
| `/api/v1/transfers/**`<br>`/api/v1/cards/**`<br>`/api/v1/payment-requests/**` | `http://financial-gateway:8082` | **Financial Gateway** (Node) | Internal/wire transfers, peer-to-peer payment requests, virtual cards engine |
| `/api/v1/risk/**`<br>`/api/v1/audit/**`<br>`/api/v1/chat/**` | `http://ai-risk-service:8083` | **AI & Risk Service** (Python) | Pre-transaction fraud scoring, audit trail consumption, AI banking assistant |
| `/**` (Root, UI pages, assets) | `http://banking-portal:8080` | **Banking Portal** (Java) | Server-rendered portal pages (`/dashboard`, `/account`), static CSS/JS fonts |

---

## 💾 Database & Event Architecture

### 1. Oracle Database 23c Free (`BANKLEDGER` Schema)
- `USERS`: Core identity records, password hashes (bcrypt cost 10), profile metadata.
- `ACCOUNTS`: Customer bank accounts, account numbers, current balance, currency, account status.
- `ACCOUNT_SECURITY`: PBKDF2-hashed transaction PINs, failed PIN attempt counter, lockout timestamps.
- `JOURNAL_ENTRIES`: Audit-sealed journal batches linking credits and debits.
- `LEDGER_POSTINGS`: Immutable debit and credit entries; enforces `SUM(CREDIT) - SUM(DEBIT) == 0`.

### 2. PostgreSQL 16 (`bank_db`)
- `spring_session` & `spring_session_attributes`: Distributed HTTP session storage for the banking portal.
- `virtual_cards`: Issued Visa / Mastercard virtual debit cards with encrypted PANs and CVV hashes.
- `payment_requests`: Peer-to-peer payment requests and settlement states (`PENDING`, `ACCEPTED`, `REJECTED`).
- `audit_events`: Asynchronously ingested transaction logs streamed from Kafka.

### 3. Apache Kafka (KRaft Mode)
- `bank.transfers.v1`: Published by Financial Gateway upon transfer execution; consumed by AI & Risk for compliance auditing.
- `bank.cards.v1`: Published on virtual card creation and card spending limit modifications.

---

## ⚡ Site24x7 Chaos SDK Integration

Every microservice in ZylkerBank includes the native **Site24x7 Labs Chaos SDK**, enabling realistic failure injection and chaos engineering simulations across polyglot runtimes.

| Service | Chaos Library Source | Integration Mechanism |
|---|---|---|
| **API Gateway** | `chaos-libs/python` (`site24x7-chaos[fastapi]`) | FastAPI middleware, patched `httpx.AsyncClient`, edge failure injection |
| **Banking Portal** | `chaos-libs/java` (`chaos-sdk-spring-boot-3`) | Auto-configuration, `RestTemplate` interceptor, `ChaosDataSourceProxy` JDBC wrapper |
| **Ledger Service** | `chaos-libs/go` (`observe-labs/sdks/go`) | Gin HTTP middleware, pure Go database connection wrapper, resource injector |
| **Financial Gateway** | `chaos-libs/nodejs` (`site24x7-chaos-sdk`) | Express middleware, patched `pg.Client.query`, patched `fetch` and `axios` clients |
| **AI & Risk Service** | `chaos-libs/python` (`site24x7-chaos[fastapi]`) | FastAPI middleware, async task interceptors, config file watcher |

### Supported Fault Types
- **HTTP Latency Injection**: Configurable fixed or jittered delays on specific routes or dependencies.
- **HTTP Error Injection**: Synthetic `500 Internal Server Error`, `502 Bad Gateway`, `503 Service Unavailable`, or connection resets.
- **Database Query Latency & Errors**: Synthetic query timeouts, connection exhaustion, and SQL execution exceptions.
- **Resource Stress**: CPU spikes, memory leaks, disk fill simulations.

### Configuration & Runtime
Fault configurations are mounted from host directory `/var/site24x7-labs/faults/` into each container:
- Gateway config: `/var/site24x7-labs/faults/api-gateway.json`
- Portal config: `/var/site24x7-labs/faults/banking-portal.json`
- Ledger config: `/var/site24x7-labs/faults/ledger-service.json`
- Gateway config: `/var/site24x7-labs/faults/financial-gateway.json`
- AI Risk config: `/var/site24x7-labs/faults/ai-risk-service.json`

The SDK dynamically watches configuration files and activates/deactivates faults with zero service restarts required.

---

## 📈 Site24x7 APM Insight Integration

ZylkerBank supports full distributed tracing and deep application performance monitoring across all polyglot microservices using the **Site24x7 APM Insight** platform.

The integration uses the **exact zero-code dynamic runtime injection** pattern from `ZylkerKart_Ecommerce`: no agent binaries or APM libraries are baked into the Docker images, ensuring development images remain lean and zero-overhead when running locally or in CI/CD without APM credentials.

### Zero-Code Agent Injection

| Service | Runtime | Injection Mechanism | Agent Artifact / Mode |
|---|---|---|---|
| **Banking Portal** | Java 17 | Dynamic download & `-javaagent` JVM flag | `apminsight-javaagent.jar` (cached in `s247_java_portal` volume) |
| **Account & Ledger** | Go 1.26 | eBPF sidecar container (`s247-go-apm-agent`) | `site24x7/apminsight-go-agent:latest` attached via host PID & container network |
| **Financial Gateway** | Node.js 18 | Dynamic npm install & Node preload flag | `npm install apminsight` + `node -r apminsight src/app.js` |
| **AI & Risk Service** | Python 3.11 | Dynamic S247DataExporter daemon + runner | `InstallDataExporter.sh` + `pip install apminsight` + `apminsight-run` |
| **API Gateway** | Python 3.11 | Dynamic S247DataExporter daemon + runner | `InstallDataExporter.sh` + `pip install apminsight` + `apminsight-run` |

### Enabling APM Monitoring

To enable APM monitoring, supply your Site24x7 license key and enable the `apm` profile:

```bash
# Start all services with Site24x7 APM Insight enabled:
S247_APM_ENABLED=true S247_LICENSE_KEY=<your_license_key> docker compose --profile apm up -d
```

Alternatively, configure your credentials in a `.env` file:

```env
S247_APM_ENABLED=true
S247_LICENSE_KEY=your_site24x7_license_key
```

Then run:
```bash
docker compose --profile apm up -d
```

When `S247_APM_ENABLED=false` (the default) or when started without the `--profile apm` flag:
```bash
docker compose up -d
```
All services run purely natively with zero agent overhead, and the Go eBPF sidecar remains inactive.

---

## 👤 Demo Credentials

Pre-seeded accounts are immediately available for login:

| Customer Name | Email Address | Password | Transaction PIN | Initial Balance | Account Number |
|---|---|---|---|---|---|
| **Destiny Franks** | `desphixs@gmail.com` | `Password@123` | `1234` | $12,434.00 | `2178392293767` |
| **Alice Johnson** | `alice@zylkerbank.com` | `Password@123` | `1234` | $8,500.00 | `2170000001` |
| **Bob Smith** | `bob@zylkerbank.com` | `Password@123` | `1234` | $5,200.00 | `2170000002` |
| **Charlie Davis** | `charlie@zylkerbank.com` | `Password@123` | `1234` | $1,500.00 | `2170000003` |

---

## 🚀 Deployment & Quick Start

### Prerequisites
- Docker Engine 24.0+ and Docker Compose v2.20+
- Host ports: `8000` (API Gateway), `8080`, `8081`, `8082`, `8083`, `1521`, `5432`, `9092`

### Start Application
### Docker Compose

From the `Applications/ZylkerBank_Fintech` directory:

```bash
# Using the deployment helper script (recommended):
./scripts/deploy-compose.sh up

# Or directly with Docker Compose:
docker compose up -d

# Start with Site24x7 APM monitoring:
S247_APM_ENABLED=true S247_LICENSE_KEY=<your_key> docker compose --profile apm up -d
```

### Kubernetes (k8s)

ZylkerBank includes native Kubernetes manifests and deployment automation under [`k8s/`](k8s/):

```bash
# Deploy all datastores, microservices, and ingress to Kubernetes:
./scripts/deploy-k8s.sh

# Or with Site24x7 APM enabled:
S247_LICENSE_KEY=<your_key> ./scripts/deploy-k8s.sh

# Check pod and service status:
./scripts/deploy-k8s.sh status

# Redeploy a single microservice:
./scripts/deploy-k8s.sh banking-portal

# Teardown the zylkerbank namespace:
./scripts/deploy-k8s.sh delete
```

#### What's in `k8s/`:
- **`00-namespace.yaml`**: Dedicated `zylkerbank` namespace.
- **`01-configmap-secrets.yaml`**: Centralized configuration, endpoints, and credentials.
- **`02-db-init-configmaps.yaml`**: Pre-loaded Oracle 23c Free and PostgreSQL 16 DDL/seed scripts.
- **`03-datastores.yaml`**: Stateful deployments for Oracle 23c Free (PVC 15Gi), PostgreSQL 16 (PVC 5Gi), and Apache Kafka KRaft (PVC 5Gi) with automatic topic creation.
- **`04-services.yaml`**: Deployments & Services for all 5 polyglot services using `impazhani/zylkerbank-*` images, complete with Site24x7 APM init containers and Chaos SDK volume mounts.
- **`05-ingress.yaml`**: NGINX Ingress rules directing traffic to `api-gateway:8000`.
- **`06-go-apm-daemonset.yaml`**: Cluster-wide eBPF DaemonSet monitoring Go microservices.

### Developer Scripts

The `scripts/` directory provides workflow automation matching the ZylkerKart development experience:

- **`./scripts/build-all.sh`**: Interactive CLI script to build multi-arch images (`linux/amd64,linux/arm64`), push manifests to Docker Hub (`impazhani/zylkerbank-<service>:latest`), or pull pre-built images.
- **`./scripts/deploy-compose.sh {up|down|restart|logs|status|clean}`**: Manages container lifecycle, polls service health probes, and presents a status dashboard.

### CI/CD Automation (GitHub Actions)

The repository includes [`.github/workflows/zylkerbank-docker.yml`](../../.github/workflows/zylkerbank-docker.yml) for automated builds:
- Triggers automatically on pushes to `main` modifying services or `chaos-libs/`.
- Supports `workflow_dispatch` manual execution with a target service dropdown (`all` or individual services).
- Builds multi-arch (`amd64`/`arm64`) with layer caching and pushes to Docker Hub (`impazhani/zylkerbank-<service>:latest`).

### Access Application
You can now access the full platform directly through the **API Gateway** on port **8000**:
- Web Banking Portal: [http://localhost:8000](http://localhost:8000) (or directly at [http://localhost:8080](http://localhost:8080))
- Gateway Route Catalog: [http://localhost:8000/api/v1/routes](http://localhost:8000/api/v1/routes)
- Interactive OpenAPI Docs: [http://localhost:8000/docs](http://localhost:8000/docs)

### Stop Application
```bash
docker compose down
```

---

## 🔍 Health & Verification Endpoints

Each microservice exposes a standardized health probe returning JSON status and dependency checks:

| Service | Method & URL | Sample Health Status |
|---|---|---|
| **API Gateway** | `GET http://localhost:8000/health` | `{"status":"UP","service":"api-gateway","downstream":{...}}` |
| **Banking Portal** | `GET http://localhost:8080/health` | `{"status":"UP","service":"banking-portal"}` |
| **Ledger Service** | `GET http://localhost:8081/health` | `{"status":"UP","service":"ledger-service","checks":{"oracle":"UP"}}` |
| **Financial Gateway** | `GET http://localhost:8082/health` | `{"status":"UP","service":"financial-gateway","checks":{"postgres":"UP","kafka":"UP"}}` |
| **AI & Risk Service** | `GET http://localhost:8083/health` | `{"status":"UP","service":"ai-risk-service","database":"connected","kafka":"connected"}` |

---

## 📑 Backend API Contracts

For complete inter-service endpoints, JSON request/response payloads, and security schemas, consult [CONTRACTS.md](CONTRACTS.md).
