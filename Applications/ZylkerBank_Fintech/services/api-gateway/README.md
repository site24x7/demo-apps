# ZylkerBank API Gateway (Python / FastAPI)

The **API Gateway** acts as the single unified edge entrypoint for ZylkerBank. It handles routing, reverse proxying, correlation ID injection.

## Routing Architecture

| Path Pattern | Target Microservice | Description |
|---|---|---|
| `/api/v1/ledger/**`, `/api/v1/accounts/**`, `/api/v1/auth/**`, `/api/v1/users/**` | `http://ledger-service:8081` | Core banking ledger, accounts, auth, PINs |
| `/api/v1/transfers/**`, `/api/v1/cards/**`, `/api/v1/payment-requests/**` | `http://financial-gateway:8082` | Transfer execution, virtual card lifecycle |
| `/api/v1/risk/**`, `/api/v1/audit/**`, `/api/v1/chat/**` | `http://ai-risk-service:8083` | Fraud risk scoring, audit stream, AI chatbot |
| `/**` (Web pages, assets, BFF) | `http://banking-portal:8080` | Banking UI, Thymeleaf SSR, assets |

## Endpoints

- `GET /health` — Aggregated health check reporting status of gateway and all downstream services.
- `GET /api/v1/routes` — Introspection endpoint listing active routing table.
- `GET /docs` — Interactive OpenAPI documentation.


