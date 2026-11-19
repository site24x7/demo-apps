# ZylkerBank Banking Portal & BFF Service

Service 1 of the **ZylkerBank Polyglot Fintech** platform.

- **Stack**: Java 17, Spring Boot 3.2.5, Thymeleaf SSR, Spring Session JDBC (PostgreSQL).
- **Port**: `8080`
- **Dependencies**: Ledger Service (`:8081`), Financial Gateway (`:8082`), AI & Risk Service (`:8083`), PostgreSQL (`bank_db`).

---

## Architecture & Layers

1. **Presentation (Thymeleaf SSR)**:
   - Responsive UI templates with ZylkerBank branding and layout fragments.
   - 3-step P2P transfer wizard (`/transfer/step-1` -> `/step-2` -> `/step-3` -> `/success`).
   - Payment request workflows (`/receive/step-1` -> `/step-2` -> `/step-3`, `/receive/requests`).
   - Virtual Card issuance, funding, withdrawal, and freeze/unfreeze (`/cards`, `/cards/{id}`).
   - Double-entry ledger account statements with pagination (`/transactions`).
   - Floating AI assistant chat widget communicating via `/api/chat`.

2. **Session Persistence**:
   - `spring-session-jdbc` persisting sessions to PostgreSQL table `spring_session` (zero Redis).
   - Session wizard state holding unique client `Idempotency-Key` (UUID).

3. **HTTP Client & Tracing**:
   - Outbound calls via `RestTemplate` backed by Apache HttpClient 5 connection pool.
   - W3C `traceparent` and correlation IDs automatically injected into all downstream requests.

4. **Security & Interceptors**:
   - `AuthInterceptor`: Protects customer routes (`/dashboard`, `/cards/**`, `/transfer/**`, etc.).
   - `CsrfInterceptor`: Generates and enforces CSRF tokens across form posts and AJAX calls.
   - Global `@ControllerAdvice` handling `BackendException` without leaking internal traces.

5. **Site24x7 Chaos SDK**:
   - Injected via `chaos-sdk-spring-boot-3` from `../../../../chaos-libs/java`.

---

## Configuration Properties

| Property | Default | Description |
|---|---|---|
| `server.port` | `8080` | HTTP service port |
| `LEDGER_URL` | `http://localhost:8081` | Go Ledger Service |
| `GATEWAY_URL` | `http://localhost:8082` | Node Financial Gateway |
| `AI_URL` | `http://localhost:8083` | Python AI & Risk Service |
| `DB_HOST` | `localhost` | PostgreSQL Host |
| `DB_PORT` | `5432` | PostgreSQL Port |
| `DB_NAME` | `bank_db` | PostgreSQL Database |
| `DB_USER` | `postgres` | PostgreSQL User |
| `DB_PASSWORD` | `ZylkerBank@2024` | PostgreSQL Password |

---

## Build & Test

```bash
# Compile and run unit/slice tests with in-memory H2 session store
mvn clean test

# Package executable JAR
mvn package -DskipTests
```
