# 🛒 ZylkerKart — Polyglot Microservices E-Commerce Platform

ZylkerKart is a full-featured e-commerce platform built with **6 microservices across 6 programming languages**, designed for demonstrating **application performance monitoring (APM)** and **observability** in distributed systems.

---

## 📋 Table of Contents

- [Application Overview](#-application-overview)
- [Architecture Diagram](#-architecture-diagram)
- [Microservices](#-microservices)
- [Tech Stack](#-tech-stack)
- [Database Schema](#-database-schema)
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
- **APM Monitoring** — Site24x7 APM integration for all services

---

## 🏛 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CLIENTS                                        │
│                         (Browser / Mobile)                                  │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                 STOREFRONT (Java 17 / Spring Boot 3.2)                      │
│                          Port: 8080                                         │
│         SSR Pages + API Proxy to Backend Microservices                       │
└───┬──────────┬───────────┬───────────┬───────────┬──────────────────────────┘
    │          │           │           │           │
    ▼          ▼           ▼           ▼           ▼
┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
│Product │ │ Order  │ │Search  │ │Payment │ │  Auth  │
│Service │ │Service │ │Service │ │Service │ │Service │
│        │ │        │ │        │ │        │ │        │
│Java 17 │ │Node 18 │ │Go 1.21 │ │Py 3.11 │ │.NET 8  │
│Spring  │ │Express │ │  Gin   │ │FastAPI │ │ASP.NET │
│ Boot   │ │        │ │        │ │        │ │  Core  │
│:8081   │ │:8082   │ │:8083   │ │:8084   │ │:8085   │
└───┬────┘ └──┬──┬──┘ └──┬──┬──┘ └───┬────┘ └───┬────┘
    │         │  │       │  │        │           │
    │         │  │       │  │        │           │
    ▼         ▼  ▼       ▼  ▼        ▼           ▼
┌─────────────────────┐  ┌──────────────────────────┐
│     MySQL 8.0       │  │       Redis 7.0           │
│     Port: 3306      │  │       Port: 6379          │
│                     │  │                            │
│  ┌─db_product───┐   │  │  • Cart session cache     │
│  ├─db_order─────┤   │  │  • Search suggestions     │
│  ├─db_search────┤   │  │  • Rate limiting          │
│  ├─db_payment───┤   │  │                            │
│  └─db_auth──────┘   │  │                            │
└─────────────────────┘  └──────────────────────────┘
```

---

## 🔧 Microservices

| Service | Language / Framework | Port | Database | Description |
|---------|---------------------|------|----------|-------------|
| **Storefront** | Java 17 / Spring Boot 3.2 | 8080 | Redis (sessions) | Server-side rendered frontend (Thymeleaf), proxies API calls to backend services |
| **Product Service** | Java 17 / Spring Boot 3 | 8081 | `db_product` (9 tables) | Product catalog, categories, search, pagination |
| **Order Service** | Node.js 18 / Express | 8082 | `db_order` (3 tables) | Shopping cart (Redis-backed), order creation & tracking |
| **Search Service** | Go 1.21 / Gin | 8083 | `db_search` (1 table) | Autocomplete, trending searches, search logging |
| **Payment Service** | Python 3.11 / FastAPI | 8084 | `db_payment` (1 table) | Payment processing, fraud scoring, refunds |
| **Auth Service** | C# / .NET 8 (ASP.NET Core) | 8085 | `db_auth` (3 tables) | JWT authentication, user registration, token refresh |

---

## 🛠 Tech Stack

| Layer | Technology |
|-------|------------|
| **Frontend** | Thymeleaf (SSR), CSS, JavaScript |
| **Backend** | Java (Spring Boot), Node.js (Express), Go (Gin), Python (FastAPI), C# (ASP.NET Core) |
| **Database** | MySQL 8.0 (5 databases, 17 tables) |
| **Cache** | Redis 7.0 (cart sessions, storefront sessions, search cache) |
| **Containerization** | Docker, Docker Compose v3.9 |
| **Orchestration** | Kubernetes (Deployments, Services, DaemonSets, Ingress) |
| **APM** | Site24x7 APM Insight (Java, Node.js, Go, Python, .NET agents) |
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
| `GET` | `/health` | Health check |

---

##  Deployment

### Prerequisites

- **Docker** & **Docker Compose** (v2+)
- **kubectl** & a Kubernetes cluster (for K8s deployment)
- **Site24x7 license key** (optional, for APM monitoring)

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

#### Service URLs (Docker Compose)

| Service | URL |
|---------|-----|
| Storefront | http://localhost:8080 |
| Product Service | http://localhost:8081 |
| Order Service | http://localhost:8082 |
| Search Service | http://localhost:8083 |
| Payment Service | http://localhost:8084 |
| Auth Service | http://localhost:8085 |
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
6. **Deploy application services** (all 6 microservices, waits for ready)
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
├── services.yaml          # All 6 microservice Deployments + Services
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

## 📁 Project Structure

```
ZylkerKart/
├── docker-compose.yml          # Docker Compose orchestration (8 services + APM sidecar)
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
    ├── search-service/         # Go 1.21 / Gin
    ├── payment-service/        # Python 3.11 / FastAPI
    ├── auth-service/           # C# / .NET 8
    └── storefront/             # Java 17 / Spring Boot 3.2
```

---
