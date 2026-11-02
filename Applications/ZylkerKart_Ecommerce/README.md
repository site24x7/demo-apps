# 🛒 ZylkerKart — Polyglot Microservices E-Commerce Platform

ZylkerKart is a full-featured e-commerce platform built with **7 microservices across 6 programming languages**, designed for demonstrating **application performance monitoring (APM)**, **LLM observability** and **observability** in distributed systems.

---

## 📋 Table of Contents

- [Application Overview](#-application-overview)
- [Architecture Diagram](#-architecture-diagram)
- [Microservices](#-microservices)
- [Tech Stack](#-tech-stack)
- [Database Schema](#-database-schema)
- [AI Shopping Assistant](#-ai-shopping-assistant)
- [Backend API Contracts](#-backend-api-contracts)
- [Deployment](#-deployment)
  - [Docker Compose](#-docker-compose)
  - [Kubernetes](#-kubernetes)
- [Site24x7 APM Integration](#-site24x7-apm-integration)

---

## 🏗 Application Overview

ZylkerKart simulates a real-world e-commerce platform where customers can browse products, search with autocomplete, manage a shopping cart, authenticate, place orders, and process payments.

### Key Features

- **Product Catalog** — Paginated browsing with categories, filters, and sorting
- **Full-Text Search** — Autocomplete suggestions, trending & recent searches
- **Shopping Cart** — Session-based cart with Redis caching
- **Authentication** — JWT-based auth with refresh tokens, brute-force protection
- **Order Management** — Order creation, tracking, and history
- **Payment Processing** — Mock payment with fraud scoring, refunds
- **AI Shopping Assistant** — Chat widget that searches the catalog, manages the cart and answers order questions, with pluggable LLM providers
- **APM Monitoring** — Site24x7 APM integration for all services
- **LLM Observability** — Traceloop (OpenLLMetry) traces from the AI assistant exported to Site24x7 over OTLP

---

## 🏛 Architecture Diagram

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                                        CLIENTS                                        │
│                                   (Browser / Mobile)                                  │
└───────────────────────────────────────────┬───────────────────────────────────────────┘
                                            ▼
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                         STOREFRONT (Java 17 / Spring Boot 3.2)                        │
│                                       Port: 8080                                      │
│                     SSR pages + API proxy to backend microservices                    │
└──────┬──────────────┬──────────────┬──────────────┬──────────────┬──────────────┬─────┘
       ▼              ▼              ▼              ▼              ▼              ▼
┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐
│  Product   │ │   Order    │ │   Search   │ │  Payment   │ │    Auth    │ │     AI     │
│  Service   │ │  Service   │ │  Service   │ │  Service   │ │  Service   │ │ Assistant  │
│            │ │            │ │            │ │            │ │            │ │ (internal) │
│  Java 17   │ │  Node 18   │ │  Go 1.26   │ │  Py 3.11   │ │C# / .NET 8 │ │  Py 3.11   │
│Spring Boot │ │  Express   │ │    Gin     │ │  FastAPI   │ │ASP.NET Core│ │  FastAPI   │
│   :8081    │ │   :8082    │ │   :8083    │ │   :8084    │ │   :8085    │ │   :8086    │
└──────┬─────┘ └──────┬─────┘ └──────┬─────┘ └──────┬─────┘ └──────┬─────┘ └──────┬─────┘
       ▼              ▼              ▼              ▼              ▼              ▼
┌────────────────────────────────────────────────────────────────────────┐ ┌────────────┐
│                            MySQL 8.0  :3306                            │ │ Redis 7.0  │
│                                                                        │ │   :6379    │
│                    db_product  db_order  db_search                     │ │            │
│                          db_payment  db_auth                           │ │            │
└────────────────────────────────────────────────────────────────────────┘ └────────────┘
```

- The AI Assistant is only reachable through the storefront (`POST /api/chat`). It calls the Product, Order and Search services as tools, talks to an LLM provider (Ollama by default), and exports LLM traces to Site24x7 over OTLP. It has no database of its own.
- Redis holds the storefront sessions, the shopping cart (Order Service), the search cache (Search Service) and the AI chat history (AI Assistant).

---

## 🔧 Microservices

| Service | Language / Framework | Port | Database | Description |
|---------|---------------------|------|----------|-------------|
| **Storefront** | Java 17 / Spring Boot 3.2 | 8080 | Redis (sessions) | Server-side rendered frontend (Thymeleaf), proxies API calls to backend services |
| **Product Service** | Java 17 / Spring Boot 3 | 8081 | `db_product` (9 tables) | Product catalog, categories, search, pagination |
| **Order Service** | Node.js 18 / Express | 8082 | `db_order` (3 tables) | Shopping cart (Redis-backed), order creation & tracking |
| **Search Service** | Go 1.26 / Gin | 8083 | `db_search` (1 table) | Autocomplete, trending searches, search logging |
| **Payment Service** | Python 3.11 / FastAPI | 8084 | `db_payment` (1 table) | Payment processing, fraud scoring, refunds |
| **Auth Service** | C# / .NET 8 (ASP.NET Core) | 8085 | `db_auth` (3 tables) | JWT authentication, user registration, token refresh |
| **AI Assistant** | Python 3.11 / FastAPI + LiteLLM | 8086 (internal) | Redis (chat history) | Shopping assistant: LLM tool-calling over the product, order and search APIs; Traceloop → Site24x7 LLM traces |

---

## 🛠 Tech Stack

| Layer | Technology |
|-------|------------|
| **Frontend** | Thymeleaf (SSR), CSS, JavaScript |
| **Backend** | Java (Spring Boot), Node.js (Express), Go (Gin), Python (FastAPI), C# (ASP.NET Core) |
| **AI / LLM** | LiteLLM (Ollama, OpenAI, Anthropic, Azure OpenAI, Groq, any OpenAI-compatible endpoint), Traceloop / OpenLLMetry |
| **Database** | MySQL 8.0 (5 databases, 17 tables) |
| **Cache** | Redis 7.0 (cart sessions, storefront sessions, search cache, AI chat history) |
| **Containerization** | Docker, Docker Compose v3.9 |
| **Orchestration** | Kubernetes (Deployments, Services, DaemonSets, Ingress) |
| **APM** | Site24x7 APM Insight (Java, Node.js, Go, Python, .NET agents) |
| **LLM observability** | Traceloop (OpenLLMetry) → Site24x7 OTLP endpoint |
| **Monitoring** | Site24x7 Server Agent, MySQL monitoring, Kube State Metrics |

---

## 🗄 Database Schema

### `db_product` — Product Catalog (9 tables)

| Table | Key Columns |
|-------|-------------|
| `category_groups` | id, name |
| `subcategories` | id, name, category_group_id |
| `products` | product_id, title, description, rating, initial_price, discount, final_price, subcategory_id, delivery_options (JSON), product_details (JSON) |
| `product_images` | id, product_id, image_url, image_order |
| `product_specifications` | id, product_id, spec_name, spec_value |
| `product_sizes` | id, product_id, size |
| `product_offers` | id, product_id, offer_name, offer_value |
| `star_ratings` | product_id, star_1 … star_5 |
| `breadcrumbs` | id, product_id, breadcrumb_order, name, url |

### `db_order` — Order Management (3 tables)

| Table | Key Columns |
|-------|-------------|
| `customers` | id, user_id, session_id, name, email, phone |
| `orders` | id, customer_id, user_id, total_amount, status, shipping_address |
| `order_items` | id, order_id, product_id, product_title, quantity, unit_price, size, image_url |

### `db_search` — Search & Autocomplete (1 table)

| Table | Key Columns |
|-------|-------------|
| `search_logs` | id, query, session_id, results_count, created_at |

### `db_payment` — Payment Transactions (1 table)

| Table | Key Columns |
|-------|-------------|
| `transactions` | id, order_id, user_id, amount, currency, method, status, transaction_ref, fraud_score |

### `db_auth` — Authentication (3 tables)

| Table | Key Columns |
|-------|-------------|
| `users` | id, email, password_hash, full_name, phone, is_locked, failed_attempts |
| `refresh_tokens` | id, user_id, token, expires_at, is_revoked |
| `user_activity` | id, user_id, activity_type (login/logout/register/order_placed/payment_success), metadata (JSON) |

---

## 🤖 AI Shopping Assistant

A floating chat button on every storefront page opens a shopping assistant. Shoppers can ask it to find products, add them to the cart, check the cart, look up past orders and see trending searches. Replies come back as text plus clickable product, cart, order and trending cards.

### How it works

```
Browser ──POST /api/chat | /api/chat/stream──▶ Storefront ──X-Internal-Token──▶ AI Assistant :8086
                                                                                    │
                                          LLM (LiteLLM) ◀── tool-calling loop ──────┤
                                                                                    ├─▶ Product Service  (search_products, get_product)
                                                                                    ├─▶ Order Service    (get_cart, add_to_cart, get_user_orders)
                                                                                    ├─▶ Search Service   (get_trending)
                                                                                    └─▶ Redis            (conversation history)
```

- The LLM chooses which tool to call. The assistant service makes the HTTP calls and feeds the results back, for up to `AI_MAX_TOOL_ROUNDS` (default 4) rounds.
- **Identity comes from the server session.** The storefront adds the session id and the logged-in user id; the browser never supplies them, and tools ignore any ids the model invents.
- The assistant port is **not published**. Only the storefront can reach it, and every call must carry the shared `X-Internal-Token`.
- **Rate limit:** the storefront allows 10 chat requests per minute per session (`AI_RATE_LIMIT_PER_MINUTE`) and answers `429` beyond that.
- **Conversation history:** the last 8 turns per session are kept in Redis for an hour (`AI_HISTORY_TURNS`, `AI_HISTORY_TTL_SEC`), so follow-ups like "show me more of those" work. Without Redis the assistant still works but has no memory.

### Tools

| Tool | What it does | Backend |
|------|--------------|---------|
| `search_products` | Search the catalog by keyword, category and max price | Product Service |
| `get_product` | Full details for one product | Product Service |
| `get_cart` | Current shopper's cart | Order Service |
| `add_to_cart` | Add a product to the current shopper's cart | Order Service |
| `get_user_orders` | Recent orders for the logged-in shopper | Order Service |
| `get_trending` | Trending search queries | Search Service |

### LLM providers

The default is **Ollama** running on the Docker host (`gemma4:latest`). Switch providers with environment variables, no code change:

| Provider | `LLM_PROVIDER` | Required settings |
|----------|----------------|-------------------|
| Ollama (default) | `ollama` | `LLM_MODEL`, optional `LLM_BASE_URL` (default `http://host.docker.internal:11434`) |
| OpenAI | `openai` | `OPENAI_API_KEY` (or `LLM_API_KEY`), `LLM_MODEL` |
| Anthropic | `anthropic` | `ANTHROPIC_API_KEY` (or `LLM_API_KEY`), `LLM_MODEL` |
| Azure OpenAI | `azure` | `AZURE_API_KEY`, `AZURE_API_BASE`, `LLM_MODEL` (deployment), optional `LLM_API_VERSION` |
| Groq | `groq` | `GROQ_API_KEY` (or `LLM_API_KEY`), `LLM_MODEL` |
| OpenAI-compatible | `compatible` | `LLM_BASE_URL`, `LLM_MODEL`, optional `LLM_API_KEY` |

```bash
# Example: use OpenAI instead of Ollama
LLM_PROVIDER=openai LLM_MODEL=gpt-4o-mini OPENAI_API_KEY=sk-... docker compose up --build -d
```

The provider is read once and cached. After changing provider settings, restart the `ai-assistant` container (or call `POST /reload` with the internal token).

The chat works with no keys at all as long as Ollama is running on the host. If it isn't, the rest of the shop is unaffected, and the assistant replies that the model is unavailable.

### Endpoints

Storefront (`:8080`):

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/chat` | Send a message (`message`, optional `page_context`); returns `reply`, `cards`, `tools_used`, `provider`, `model` |
| `POST` | `/api/chat/stream` | Same, as a Server-Sent Events stream of progress events followed by the final result |
| `GET` | `/api/chat/suggestions` | Search autocomplete (`q`) for the chat input |

AI Assistant (`:8086`, internal; all except `/health` need `X-Internal-Token`):

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Status plus an LLM reachability probe (for Ollama, `GET /api/tags`) |
| `POST` | `/chat` | Chat request from the storefront |
| `POST` | `/chat/stream` | SSE variant |
| `POST` | `/reload` | Clear and retry the cached provider |

### Observability

- **LLM traces:** Traceloop (OpenLLMetry) is initialised at startup and exports spans (workflow, tool calls, LLM calls) to Site24x7 over OTLP. Set `OTEL_EXPORTER_OTLP_HEADERS=api-key=<your Site24x7 license key>` so Site24x7 accepts them. Without the key the service still starts and answers chats (a tracing failure never blocks it), but the exports are unauthenticated and won't show up in Site24x7. The endpoint defaults to `https://otel.site24x7rum.com` (`OTEL_EXPORTER_OTLP_ENDPOINT`) and the service name is `zylkerkart-ai-assistant`.
- **Chaos:** the assistant embeds the same FastAPI Chaos SDK as the Payment Service (`CHAOS_SDK_*`).
- **Privacy:** by default Traceloop records prompts and completions in the spans, so shopper chat text can appear in exported traces. Only set the OTLP headers when you intend that.

See [`services/ai-assistant/README.md`](services/ai-assistant/README.md) for the service itself.

---

## 📡 Backend API Contracts

### Product Service — `:8081`

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/products` | Paginated product listing (params: `category`, `subcategory`, `search`, `page`, `size`, `sort`) |
| `GET` | `/products/categories` | List all category groups with subcategories |
| `GET` | `/products/{id}` | Get single product detail |
| `GET` | `/health` | Health check |

### Order Service — `:8082`

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/cart/add` | Add item to cart (`sessionId`, `productId`, `title`, `price`, `quantity`, `size`, `image`) |
| `GET` | `/cart/:sessionId` | Get cart contents |
| `PUT` | `/cart/:sessionId/item/:productId` | Update item quantity |
| `DELETE` | `/cart/:sessionId/item/:productId` | Remove item from cart |
| `DELETE` | `/cart/:sessionId` | Clear entire cart |
| `POST` | `/orders` | Create order from cart (`sessionId`, `customer`) |
| `GET` | `/orders/user/:userId` | Get orders by user ID |
| `GET` | `/orders/session/:sessionId` | Get orders by session ID |
| `GET` | `/orders/:id` | Get order details |

### Search Service — `:8083`

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/search/suggestions` | Autocomplete suggestions (params: `q`, `limit=8`) |
| `GET` | `/search/trending` | Trending searches (param: `limit=10`) |
| `GET` | `/search/recent` | Recent searches (params: `session_id`, `limit=5`) |
| `POST` | `/search/log` | Log a search query (`query`, `sessionId`, `resultsCount`) |

### Payment Service — `:8084`

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/payments/process` | Process a payment (`order_id`, `user_id`, `amount`, `currency`, `method`) |
| `GET` | `/payments/{transaction_ref}` | Get transaction by reference |
| `GET` | `/payments/order/{order_id}` | Get transactions for an order |
| `POST` | `/payments/refund` | Process a refund (`transaction_ref`, `reason`) |

### Auth Service — `:8085`

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/auth/register` | Register new user (`email`, `password`, `fullName`, `phone`, `address`) |
| `POST` | `/auth/login` | Login (`email`, `password`) → returns JWT + refresh token |
| `POST` | `/auth/refresh` | Refresh JWT (`refreshToken`) |
| `GET` | `/auth/validate` | Validate bearer token (Authorization header) |
| `POST` | `/auth/logout` | Logout / revoke refresh token (`refreshToken`) |

### Storefront — `:8080`

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/` | Home page |
| `GET` | `/products` | Product listing page |
| `GET` | `/products/{id}` | Product detail page |
| `GET` | `/cart` | Cart page |
| `GET` | `/login` | Login page |
| `POST` | `/login` | Submit login |
| `GET` | `/register` | Registration page |
| `POST` | `/register` | Submit registration |
| `POST` | `/logout` | Logout |
| `GET` | `/checkout` | Checkout page |
| `POST` | `/checkout` | Place order |
| `GET` | `/orders` | Order history page |
| `POST` | `/api/chat` | AI assistant chat (see [AI Shopping Assistant](#-ai-shopping-assistant)) |
| `POST` | `/api/chat/stream` | AI assistant chat, streamed (SSE) |
| `GET` | `/api/chat/suggestions` | Search autocomplete for the chat input |
| `GET` | `/health` | Health check |

---

##  Deployment

### Prerequisites

- **Docker** & **Docker Compose** (v2+)
- **kubectl** & a Kubernetes cluster (for K8s deployment)
- **Site24x7 license key** (optional, for APM monitoring)

---

### 📦 Site24x7 Chaos SDK

Every service embeds the Site24x7 Labs Chaos SDK. The SDK is **not** pulled from
npm, PyPI, NuGet, Maven or Go module proxies. It ships in the repo-root
[`chaos-libs/`](../../chaos-libs) folder, which holds the current release for all
five languages (one shared version, see `chaos-libs/VERSION`). No tokens or
registry credentials are needed to build.

| Service | Manifest entry |
|---------|----------------|
| order-service | `package.json` → `file:../../../../chaos-libs/nodejs/site24x7-chaos-sdk-<V>.tgz` |
| payment-service, ai-assistant | `requirements.txt` → `--find-links ../../../../chaos-libs/python` + `site24x7-chaos[fastapi]==<V>` |
| auth-service | `AuthService.csproj` → `Site24x7.Chaos` `<V>` via the local feed in `nuget.config` |
| search-service | `go.mod` → `observe-labs/sdks/go v<V>` + `replace … => ../../../../chaos-libs/go` |
| product-service, storefront | `pom.xml` → `<chaos-sdk.version>` + a `file://` repository at `chaos-libs/java` |

The paths are relative to each service folder, so they work in a plain checkout.
Each Dockerfile mirrors the repo layout and gets `chaos-libs/` through a named
build context:

```bash
# docker compose sets this up already (additional_contexts in docker-compose.yml)
docker buildx build --build-context chaos-libs=../../chaos-libs services/order-service
```

New SDK releases are committed to `chaos-libs/` by the observe-labs release
workflow, which bumps every reference above in the same commit. Don't edit the
version numbers by hand.

---

### 🐳 Docker Compose

#### Quick Start (without APM)

```bash
docker compose up --build
```

#### With Site24x7 APM Monitoring

```bash
S247_APM_ENABLED=true S247_LICENSE_KEY=<your_key> docker compose --profile apm up --build -d
``

Or create a `.env` file:

```env
S247_APM_ENABLED=true
S247_LICENSE_KEY=your_license_key_here
```

Then run:

```bash
docker compose up --build
```

#### AI assistant (Docker Compose)

The `ai-assistant` service starts with the rest of the stack. By default it talks to **Ollama on your host** (`http://host.docker.internal:11434`, model `gemma4:latest`), so start Ollama and pull the model first, or point it at another provider (see [LLM providers](#llm-providers)). To export LLM traces to Site24x7, set `OTEL_EXPORTER_OTLP_HEADERS=api-key=<license key>`.

#### Service URLs (Docker Compose)

| Service | URL |
|---------|-----|
| Storefront | http://localhost:8080 |
| Product Service | http://localhost:8081 |
| Order Service | http://localhost:8082 |
| Search Service | http://localhost:8083 |
| Payment Service | http://localhost:8084 |
| Auth Service | http://localhost:8085 |
| AI Assistant | internal only (reached through the storefront chat widget) |
| MySQL | localhost:3306 |
| Redis | localhost:6379 |

#### APM Toggle

The `S247_APM_ENABLED` environment variable controls APM instrumentation:

- **`false` (default)** — Services run normally with zero APM overhead
- **`true`** — APM agents are downloaded, installed, and attached at container startup

Each service is instrumented using language-specific Site24x7 APM agents:

| Service | APM Agent Method |
|---------|-----------------|
| Product Service (Java) | `-javaagent` flag with `apminsight-javaagent.jar` |
| Order Service (Node.js) | `node -r apminsight` preload flag |
| Search Service (Go) | eBPF sidecar container (`s247-go-apm-agent`) |
| Payment Service (Python) | `apminsight-run` wrapper + S247DataExporter |
| Auth Service (.NET) | CoreCLR profiler environment variables |
| Storefront (Java) | `-javaagent` flag with `apminsight-javaagent.jar` |
| AI Assistant (Python) | LLM traces via Traceloop → Site24x7 OTLP (`OTEL_EXPORTER_OTLP_*`); the APM agent is added in the Kubernetes deployment |

---

### ☸ Kubernetes

#### Deploy

Run the deploy script — it will interactively prompt for your Site24x7 license key:

```bash
./scripts/deploy-k8s.sh
```

The script performs 10 sequential steps:

1. **Build Docker images** (prompts: local-only or push to Docker Hub)
2. **Create namespace** (`zylkerkart`)
3. **Apply ConfigMap** (injects Site24x7 key if provided)
4. **Deploy MySQL** (waits for ready)
5. **Deploy Redis** (waits for ready)
6. **Deploy application services** (everything under `k8s/services/`, waits for ready)
7. **Apply Ingress** rules
8. **Deploy Site24x7 Go APM DaemonSet** (if key provided)
9. **Deploy Site24x7 Server Agent** DaemonSet (if key provided)
10. **Configure MySQL monitoring** in Site24x7 agent (auto-runs `AgentManager.sh mysql --add_instance`)

#### Access (Kubernetes)

Add to `/etc/hosts`:

```
127.0.0.1  zylkerkart.local
```

| Service | URL |
|---------|-----|
| Storefront | http://zylkerkart.local |

Or port-forward individual services:

```bash
kubectl -n zylkerkart port-forward svc/storefront 8080:80
kubectl -n zylkerkart port-forward svc/product-service 8081:8081
```

#### K8s Manifests

```
k8s/
├── namespace.yaml         # zylkerkart namespace
├── configmap.yaml         # Shared config (DB, Redis, JWT, S247 key)
├── mysql.yaml             # MySQL Deployment + PVC + Service
├── redis.yaml             # Redis Deployment + Service
├── services.yaml          # Microservice Deployments + Services
├── ingress.yaml           # Ingress rules for storefront
├── go-apm-daemonset.yaml  # Site24x7 Go APM eBPF DaemonSet
└── site24x7-agent.yaml    # Site24x7 Server Agent DaemonSet + RBAC + KSM
```

---

## 📊 Site24x7 APM Integration

ZylkerKart integrates with **Site24x7 APM Insight** for application performance monitoring across all microservices.

### Docker Compose

Enable via environment variables:

```bash
S247_APM_ENABLED=true S247_LICENSE_KEY=<your_key> docker compose up
```

### Kubernetes

The deploy script (`deploy-k8s.sh`) handles everything:
- Prompts for the license key at runtime
- Injects it into the ConfigMap and Kubernetes Secret
- Deploys Go APM eBPF DaemonSet for search-service
- Deploys Site24x7 Server Agent DaemonSet with auto MySQL monitoring
- APM agents for Java, Node.js, Python, .NET, and Go are configured via init containers and environment variables in `services.yaml`

> **AI assistant on Kubernetes:** the AI assistant is deployed by the Terraform Kubernetes deployment (EKS/AKS), which also wires its LLM settings and OTLP export. See [`Terraform Deployment/README.md`](../../Terraform%20Deployment/README.md). The shell-script path above does not include it.

## 📁 Project Structure

```
ZylkerKart/
├── docker-compose.yml          # Docker Compose orchestration (9 containers + APM sidecar)
├── README.md
├── db/                         # MySQL initialization
│   ├── Dockerfile
│   ├── 01-schema.sql           # Database schema (5 databases, 17 tables)
│   ├── 02-seed.sh              # Data seeding script
│   ├── product_datasets.csv    # Product seed data
│   └── seed/                   # Python seed loader
├── k8s/                        # Kubernetes manifests
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── mysql.yaml
│   ├── redis.yaml
│   ├── services.yaml
│   ├── ingress.yaml
│   ├── go-apm-daemonset.yaml
│   └── site24x7-agent.yaml
├── scripts/                    # Deployment scripts
│   ├── build-all.sh            # Build all Docker images (local or push to Hub)
│   ├── deploy-compose.sh       # Docker Compose deployment
│   └── deploy-k8s.sh           # Kubernetes deployment (interactive)
└── services/                   # Microservices source code
    ├── product-service/        # Java 17 / Spring Boot 3
    ├── order-service/          # Node.js 18 / Express
    ├── search-service/         # Go 1.26 / Gin
    ├── payment-service/        # Python 3.11 / FastAPI
    ├── auth-service/           # C# / .NET 8
    ├── storefront/             # Java 17 / Spring Boot 3.2 (incl. chat proxy)
    └── ai-assistant/           # Python 3.11 / FastAPI + LiteLLM (AI shopping assistant)

../../chaos-libs/               # Site24x7 Chaos SDK (all languages, current version)
```

---
