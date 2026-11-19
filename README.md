# Site24x7 Demo Apps

This repository contains enterprise-grade demo applications and automated deployment workflows for showcasing **Site24x7's full-stack observability** capabilities — including APM Insight, infrastructure monitoring, log management, chaos engineering, and real user monitoring across polyglot microservice architectures.

---

## 📱 Applications

| Application | Description | Tech Stack | Ports / Ingress |
|-------------|-------------|------------|-----------------|
| [**ZylkerKart E-Commerce**](Applications/ZylkerKart_Ecommerce/) | Polyglot microservices e-commerce platform with 7 services across 6 languages, shopping cart, order tracking, and an AI shopping assistant with LLM observability. | Java, Node.js, Go, Python, C#/.NET, MySQL 8.0, Redis 7.0, LiteLLM | `:8080` (Storefront BFF)<br>`:8081`–`:8085` (Backends) |
| [**ZylkerBank Fintech**](Applications/ZylkerBank_Fintech/) | Enterprise digital banking platform with 5 polyglot microservices, unified asynchronous Edge API Gateway, immutable double-entry accounting ledger, Kafka event streaming, and AI risk scoring. | Python, Java, Go, Node.js, Oracle 23c Free, PostgreSQL 16, Apache Kafka (KRaft) | `:8000` (API Gateway)<br>`:8080` (Banking Portal)<br>`:8081`–`:8083` (Services) |

---

## 🏦 ZylkerBank Fintech Platform Overview

ZylkerBank is purpose-built for demonstrating modern distributed fintech architectures, dual-database consistency, event-driven streaming, and deep Site24x7 observability:

- **API Gateway (Port 8000)**: Asynchronous edge router (FastAPI / HTTPX) providing reverse-proxying, correlation ID injection, and edge fault simulation.
- **Banking Portal (Port 8080)**: Server-side rendered digital banking UI (Java 17 / Spring Boot 3.2 / Thymeleaf) with distributed PostgreSQL session storage.
- **Ledger Service (Port 8081)**: High-integrity double-entry accounting engine (Go 1.26 / Gin) running ACID journal postings against **Oracle Database 23c Free**.
- **Financial Gateway (Port 8082)**: Transfer orchestrator and AES-256 virtual card engine (Node.js 18 / Express) producing events to **Apache Kafka**.
- **AI & Risk Intelligence (Port 8083)**: Real-time fraud scoring engine, Kafka audit consumer, and AI banking assistant (Python 3.11 / FastAPI).

### Quick Start (ZylkerBank)

```bash
cd Applications/ZylkerBank_Fintech

# 1. Start all datastores, microservices, and API Gateway:
./scripts/deploy-compose.sh up

# 2. Or start with Site24x7 APM Insight enabled:
S247_APM_ENABLED=true S247_LICENSE_KEY=<your_key> docker compose --profile apm up -d

# 3. Deploy to Kubernetes:
./scripts/deploy-k8s.sh

# Web Access:
# - Banking Web Portal: http://localhost:8000 (or http://localhost:8080)
# - Interactive API Docs: http://localhost:8000/docs
# - Seed Demo Login: desphixs@gmail.com / Password@123 (PIN: 1234)
```

---

## 🛒 ZylkerKart E-Commerce Platform Overview

ZylkerKart simulates a high-scale retail shopping platform featuring:
- **Storefront BFF (Port 8080)**: Spring Boot SSR web storefront.
- **Microservices (Ports 8081–8085)**: Product catalog (Java), order & cart (Node.js / Redis), autocomplete search (Go), payment processing (Python), and user auth (C#/.NET).
- **AI Assistant (Port 8086)**: LLM tool-calling shopping agent with Traceloop OpenLLMetry observability.

### Quick Start (ZylkerKart)

```bash
cd Applications/ZylkerKart_Ecommerce

# Start via Docker Compose:
docker compose up -d

# With Site24x7 APM:
S247_APM_ENABLED=true S247_LICENSE_KEY=<your_key> docker compose --profile apm up -d
```

---

## ⚡ Site24x7 Chaos SDK & Observability

Both applications integrate the shared, in-repo **Site24x7 Chaos SDK** (`chaos-libs/`):
- **Dynamic Runtime Injection**: HTTP latency and error codes, database slow queries, connection pool exhaustion, and CPU/memory saturation via `/var/site24x7-labs/faults/*.json`.
- **Zero-Code APM Agents**: Dynamic runtime attachment for Java (`-javaagent`), Node.js (`-r apminsight`), Python (`apminsight-run`), and Go (eBPF sidecar and DaemonSet).
- **Multi-Cloud Deployment**: Automated infrastructure provisioning in `Terraform Deployment/` for AWS EKS, Azure AKS, and bare-metal environments.

---

## 👥 Maintainers

This repository is maintained by the **Product Management** team at ManageEngine.

For questions, access requests, or contributions, reach out to the maintainers or open a pull request.

## 📄 License

Internal use only — ManageEngine / Zoho Corporation.
