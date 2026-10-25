# Site24x7 Labs Chaos SDK for Go — Integration Guide

Inject realistic application-level faults into Go microservices during Site24x7 demos. Faults are controlled from the Site24x7 Labs UI, injected via this SDK embedded in the target app, and captured by Site24x7 APM to showcase its monitoring capabilities.

## Table of Contents

- [Quick Start](#quick-start)
- [Architecture Overview](#architecture-overview)
- [Supported Fault Types](#supported-fault-types)
- [Configuration Reference](#configuration-reference)
- [Docker Deployment](#docker-deployment)
- [Kubernetes Deployment](#kubernetes-deployment)
- [How It Works](#how-it-works)
- [Advanced Usage](#advanced-usage)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

### 1. Install the module

> SDKs are shipped only in [site24x7/demo-apps](https://github.com/site24x7/demo-apps) under `chaos-libs/` (see `chaos-libs/README.md` there); they are not published to a Go module proxy or tags. Paths below assume the app sits at `Applications/<app>/services/<svc>/` in demo-apps.

Requires Go 1.25+. In `go.mod`:

```go
require github.com/site24x7/observe-labs/sdks/go v<version>

replace github.com/site24x7/observe-labs/sdks/go => ../../../../chaos-libs/go
```

### 2. Add to your application

**net/http (standard library):**

```go
package main

import (
    "log"
    "net/http"

    chaos "github.com/site24x7/observe-labs/sdks/go"
    "github.com/site24x7/observe-labs/sdks/go/fault"
)

func main() {
    ci, err := chaos.InitChaos("order-service",
        chaos.WithFramework("net-http", "1.22"),
    )
    if err != nil {
        log.Fatal(err)
    }
    defer ci.Shutdown()

    mux := http.NewServeMux()
    mux.HandleFunc("/api/orders", func(w http.ResponseWriter, r *http.Request) {
        w.Write([]byte(`{"orders": []}`))
    })

    // Wrap with chaos middleware
    handler := fault.HTTPMiddleware(ci.Engine)(mux)
    http.ListenAndServe(":8080", handler)
}
```

**Gin:**

```go
package main

import (
    "log"

    "github.com/gin-gonic/gin"
    chaos "github.com/site24x7/observe-labs/sdks/go"
    ginmw "github.com/site24x7/observe-labs/sdks/go/gin"
)

func main() {
    ci, err := chaos.InitChaos("order-service",
        chaos.WithFramework("gin", "1.9"),
    )
    if err != nil {
        log.Fatal(err)
    }
    defer ci.Shutdown()

    r := gin.Default()
    r.Use(ginmw.Middleware(ci.Engine))

    r.GET("/api/orders", func(c *gin.Context) {
        c.JSON(200, gin.H{"orders": []string{}})
    })

    r.Run(":8080")
}
```

**Echo:**

```go
package main

import (
    "log"
    "net/http"

    "github.com/labstack/echo/v4"
    chaos "github.com/site24x7/observe-labs/sdks/go"
    echomw "github.com/site24x7/observe-labs/sdks/go/echo"
)

func main() {
    ci, err := chaos.InitChaos("order-service",
        chaos.WithFramework("echo", "4.11"),
    )
    if err != nil {
        log.Fatal(err)
    }
    defer ci.Shutdown()

    e := echo.New()
    e.Use(echomw.Middleware(ci.Engine))

    e.GET("/api/orders", func(c echo.Context) error {
        return c.JSON(http.StatusOK, map[string]interface{}{"orders": []string{}})
    })

    e.Start(":8080")
}
```

### 3. Set environment variables

```bash
export CHAOS_SDK_ENABLED=true
export CHAOS_SDK_APP_NAME=order-service        # Must match the name in Labs UI
export CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults
```

### 4. Mount the shared volume

The SDK reads fault configuration from a JSON file written by the Site24x7 Labs agent. Both the agent and your application must have access to the same directory.

```yaml
services:
  order-service:
    volumes:
      - chaos_config:/var/site24x7-labs/faults:ro
```

### 5. Create fault rules in the Labs UI

1. Open Site24x7 Labs (http://localhost:8890)
2. Navigate to **Fault Injection** in the sidebar
3. Click **Create Rule** and configure the fault type, target app, and probability
4. Toggle the rule **ON** to activate

That's it. No other code changes required in your application.

---

## Architecture Overview

```
Site24x7 Labs UI
       |
       | HTTP API
       v
Site24x7 Labs Server
       |
       | gRPC (ExperimentStream)
       v
Site24x7 Labs Agent
       |
       | Writes JSON config files (atomic rename)
       v
Shared Volume: /var/site24x7-labs/faults/{app_name}.json
       ^
       | Reads config file (goroutine polls every 2s)
       |
Your Go Application (with Chaos SDK)
```

### Why file-based communication?

The SDK does NOT communicate over the network (HTTP/gRPC/WebSocket). If it did, the HTTP polling calls would be captured by the Site24x7 APM agent as external API calls, creating noise in the monitoring dashboard during demos. File-based communication is completely invisible to APM.

---

## Supported Fault Types

### Inbound HTTP Faults (5 types) — net/http middleware

| Fault Type | Config Fields | Description |
|---|---|---|
| `http_exception` | `exception_class`, `message` | Return a mapped Go error as 500 response |
| `http_latency` | `delay_ms` | Add artificial latency (time.Sleep) before the handler |
| `http_error_response` | `status_code`, `body` | Return a static error response, bypassing the handler |
| `http_connection_reset` | (none) | Hijack and close the TCP connection |
| `http_slow_body` | `delay_ms`, `chunk_size_bytes` | Stream response with inter-chunk delays (chunked transfer) |

### Outbound HTTP Client Faults (4 types) — http.RoundTripper wrapper

| Fault Type | Config Fields | Description |
|---|---|---|
| `http_client_latency` | `delay_ms` | Delay before outbound HTTP call |
| `http_client_exception` | `exception_class`, `message` | Return a mapped error instead of calling |
| `http_client_error_response` | `status_code`, `body` | Return fake error response |
| `http_client_partial_response` | `status_code`, `body`, `truncate_percentage` | Return truncated response body |

### Database Faults (3 types) — database/sql driver wrapper

| Fault Type | Config Fields | Description |
|---|---|---|
| `jdbc_exception` | `exception_class`, `message`, `sql_state` | Return a database error before queries |
| `jdbc_latency` | `delay_ms` | Delay before query executes |
| `jdbc_connection_pool_drain` | `hold_count`, `hold_duration_ms` | Acquire and hold pool connections |

### Redis Faults (2 types) — go-redis v9 Hook

| Fault Type | Config Fields | Description |
|---|---|---|
| `redis_exception` | `exception_class`, `message` | Return a connection/command error |
| `redis_latency` | `delay_ms` | Delay before Redis command |

### Resource Exhaustion Faults (6 types) — config-change listener

| Fault Type | Config Fields | Description |
|---|---|---|
| `thread_pool_exhaustion` | `duration_ms`, `thread_count` | Leak goroutines blocked on channels |
| `memory_pressure` | `allocation_mb`, `duration_ms` | Allocate and hold `[]byte` slices |
| `cpu_burn` | `duration_ms`, `thread_count` | `runtime.LockOSThread` + tight math loops |
| `gc_pressure` | `duration_ms`, `allocation_rate_mb_per_sec` | Rapid short-lived allocations to stress GC |
| `thread_deadlock` | `duration_ms` | Goroutines blocked on channels with no writer |
| `disk_fill` | `allocation_mb`, `duration_ms` | Write temp files to fill disk |

---

## Fault Type Details

### http_exception

Returns a 500 response with an error message mapped from the canonical Java exception class to a Go error.

```json
{
  "fault_type": "http_exception",
  "config": {
    "exception_class": "java.lang.RuntimeException",
    "message": "Simulated runtime error"
  }
}
```

Exception class mapping (Java → Go):

| Java Exception | Go Error |
|---|---|
| `java.lang.RuntimeException` | `errors.New(message)` |
| `java.lang.NullPointerException` | `fmt.Errorf("nil pointer: %s")` |
| `java.lang.IllegalStateException` | `fmt.Errorf("illegal state: %s")` |
| `java.io.IOException` | `fmt.Errorf("I/O error: %s")` |
| `java.util.concurrent.TimeoutException` | `fmt.Errorf("timeout: %s")` |

### http_latency

Adds a `time.Sleep()` delay before the request reaches your handler.

```json
{
  "fault_type": "http_latency",
  "config": {
    "delay_ms": 5000
  }
}
```

### http_error_response

Returns an HTTP error response directly from the middleware, bypassing your handler entirely.

```json
{
  "fault_type": "http_error_response",
  "config": {
    "status_code": 503,
    "body": "{\"error\": \"Service Unavailable\"}"
  }
}
```

### http_connection_reset

Hijacks the TCP connection via `http.Hijacker` and closes it immediately. The client sees a connection reset error. Falls back to an empty 502 if hijacking is not supported.

```json
{
  "fault_type": "http_connection_reset",
  "config": {}
}
```

### http_slow_body

Streams a response body in small chunks with delays between each chunk using chunked transfer encoding.

```json
{
  "fault_type": "http_slow_body",
  "config": {
    "delay_ms": 200,
    "chunk_size_bytes": 64
  }
}
```

### http_client_latency

Adds a `time.Sleep()` delay before outbound HTTP calls made via `http.Client` with the chaos transport.

```json
{
  "fault_type": "http_client_latency",
  "config": {
    "delay_ms": 3000
  }
}
```

### http_client_exception

Returns an error from the `RoundTripper` instead of making the outbound call. The remote server is never contacted.

```json
{
  "fault_type": "http_client_exception",
  "config": {
    "exception_class": "java.net.ConnectException",
    "message": "Connection refused"
  }
}
```

### http_client_error_response

Returns a fake `http.Response` with the specified status code and body, without making a real HTTP call.

```json
{
  "fault_type": "http_client_error_response",
  "config": {
    "status_code": 503,
    "body": "Service Unavailable"
  }
}
```

### http_client_partial_response

Returns a truncated response body to simulate partial/corrupt network responses.

```json
{
  "fault_type": "http_client_partial_response",
  "config": {
    "status_code": 200,
    "body": "{\"data\": \"this will be truncated\"}",
    "truncate_percentage": 50
  }
}
```

### jdbc_exception

Returns a `DatabaseError` with an SQL state before SQL queries execute. Works with any `database/sql` driver wrapped by `chaos.WrapDriver`.

```json
{
  "fault_type": "jdbc_exception",
  "config": {
    "exception_class": "java.sql.SQLException",
    "message": "Connection refused: too many connections",
    "sql_state": "08001"
  }
}
```

### jdbc_latency

Adds a `time.Sleep()` delay before each SQL query executes.

```json
{
  "fault_type": "jdbc_latency",
  "config": {
    "delay_ms": 3000
  }
}
```

### jdbc_connection_pool_drain

Opens and holds database connections in background goroutines. Legitimate queries will timeout waiting for a connection from `sql.DB`'s pool.

```json
{
  "fault_type": "jdbc_connection_pool_drain",
  "config": {
    "hold_count": 5,
    "hold_duration_ms": 30000
  }
}
```

### redis_exception

Returns a Redis error before commands execute. Works via the go-redis v9 `Hook` interface.

```json
{
  "fault_type": "redis_exception",
  "config": {
    "exception_class": "org.springframework.data.redis.RedisConnectionFailureException",
    "message": "Connection refused"
  }
}
```

### redis_latency

Adds a `time.Sleep()` delay before each Redis command.

```json
{
  "fault_type": "redis_latency",
  "config": {
    "delay_ms": 2000
  }
}
```

### thread_pool_exhaustion (Goroutine Leak)

Spawns goroutines blocked on channels that never receive data, consuming scheduler resources.

```json
{
  "fault_type": "thread_pool_exhaustion",
  "config": {
    "thread_count": 10,
    "duration_ms": 30000
  }
}
```

### memory_pressure

Allocates large `[]byte` slices on the heap and holds them for the specified duration. Memory is touched at page boundaries to ensure real allocation.

```json
{
  "fault_type": "memory_pressure",
  "config": {
    "allocation_mb": 64,
    "duration_ms": 30000
  }
}
```

### cpu_burn

Runs tight math loops (`math.Sin * math.Cos`) in goroutines with `runtime.LockOSThread()` to pin them to OS threads.

```json
{
  "fault_type": "cpu_burn",
  "config": {
    "thread_count": 2,
    "duration_ms": 30000
  }
}
```

### gc_pressure

Rapidly allocates and discards 1MB `[]byte` slices to force frequent garbage collection.

```json
{
  "fault_type": "gc_pressure",
  "config": {
    "allocation_rate_mb_per_sec": 10,
    "duration_ms": 30000
  }
}
```

### thread_deadlock (Goroutine Deadlock)

Creates goroutines blocked on channels with no writer, simulating a deadlock. Released after the duration expires.

```json
{
  "fault_type": "thread_deadlock",
  "config": {
    "duration_ms": 30000
  }
}
```

### disk_fill

Writes temporary files to `os.TempDir()` to consume disk space. Files are cleaned up when the duration expires.

```json
{
  "fault_type": "disk_fill",
  "config": {
    "allocation_mb": 64,
    "duration_ms": 30000
  }
}
```

---

## Configuration Reference

### Environment variables

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `CHAOS_SDK_ENABLED` | boolean | `true` | No | Enable/disable the SDK entirely. Set to `false` to disable. |
| `CHAOS_SDK_APP_NAME` | string | — | Yes | Application name. Must match the `app_name` registered in Site24x7 Labs. |
| `CHAOS_SDK_CONFIG_DIR` | string | `/var/site24x7-labs/faults` | No | Directory where the agent writes config files. |

### InitChaos() options

| Option | Type | Default | Description |
|---|---|---|---|
| `chaos.WithConfigDir(dir)` | string | `/var/site24x7-labs/faults` | Overrides `CHAOS_SDK_CONFIG_DIR` |
| `chaos.WithFramework(name, version)` | string, string | `"net-http", ""` | Framework name/version for the heartbeat |
| `chaos.WithEnabled(enabled)` | bool | `true` | Overrides `CHAOS_SDK_ENABLED` |

Options passed to `InitChaos()` override environment variables.

### URL pattern matching

HTTP fault rules support an optional `url_pattern` field for targeting specific endpoints:

| Pattern | Matches |
|---|---|
| (empty) | All requests |
| `/api/orders/*` | `/api/orders/123`, `/api/orders/456` |
| `/api/**` | `/api/orders/123`, `/api/users/profile/settings` |
| `/api/orders/create` | Exact match only |

- `*` matches a single path segment (anything except `/`)
- `**` matches any number of path segments

Database and Redis fault rules do not use URL patterns — they apply to all operations.

### Config file format

The agent writes a JSON file per application. The SDK reads this file:

```json
{
  "version": 1,
  "app_name": "order-service",
  "environment_id": "5cd9410e-f0c7-435d-a891-69b02e8e9f10",
  "updated_at": "2026-02-26T10:30:00Z",
  "rules": [
    {
      "id": "a1b2c3d4-...",
      "fault_type": "http_latency",
      "enabled": true,
      "probability": 0.5,
      "config": {
        "delay_ms": 3000
      },
      "url_pattern": "/api/orders/*"
    }
  ]
}
```

You do not need to create or edit this file manually. It is managed by the Site24x7 Labs agent.

---

## Docker Deployment

### Docker Compose

Add the `chaos_config` shared volume to both the agent and your application service:

```yaml
services:
  # Site24x7 Labs Agent (already configured)
  site24x7-agent:
    image: site24x7-labs-agent:latest
    environment:
      - CHAOS_CONFIG_DIR=/var/site24x7-labs/faults
    volumes:
      - chaos_config:/var/site24x7-labs/faults

  # Your Go application
  order-service:
    image: your-org/order-service:latest
    environment:
      - CHAOS_SDK_ENABLED=true
      - CHAOS_SDK_APP_NAME=order-service
      - CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults
    volumes:
      - chaos_config:/var/site24x7-labs/faults:ro  # Read-only is sufficient

volumes:
  chaos_config:
```

> **Note**: The application only needs read access to the volume (`:ro`). The agent is the only writer. However, the SDK writes a heartbeat file, so if heartbeat-based auto-discovery is needed, use read-write access.

### Multiple applications

Each application gets its own config file within the shared directory. The filename matches the `app_name`:

```
/var/site24x7-labs/faults/
  order-service.json
  payment-service.json
  user-service.json
```

All services can share the same `chaos_config` volume.

---

## Kubernetes Deployment

### Option 1: Sidecar + emptyDir (recommended)

Run the Labs agent as a sidecar container in the same Pod. Use an `emptyDir` volume for the config files.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
spec:
  template:
    spec:
      containers:
        # Your application
        - name: order-service
          image: your-org/order-service:latest
          env:
            - name: CHAOS_SDK_ENABLED
              value: "true"
            - name: CHAOS_SDK_APP_NAME
              value: order-service
            - name: CHAOS_SDK_CONFIG_DIR
              value: /var/site24x7-labs/faults
          volumeMounts:
            - name: chaos-config
              mountPath: /var/site24x7-labs/faults

        # Site24x7 Labs Agent sidecar
        - name: labs-agent
          image: site24x7-labs-agent:latest
          env:
            - name: LABS_SERVER_ADDR
              value: "site24x7-labs-server.labs.svc:9090"
            - name: CHAOS_CONFIG_DIR
              value: /var/site24x7-labs/faults
            - name: AGENT_ENVIRONMENT_ID
              value: "5cd9410e-f0c7-435d-a891-69b02e8e9f10"
          volumeMounts:
            - name: chaos-config
              mountPath: /var/site24x7-labs/faults

      volumes:
        - name: chaos-config
          emptyDir: {}
```

### Option 2: DaemonSet + hostPath

Run a single Labs agent per node using a DaemonSet. Share config files via a `hostPath` volume.

```yaml
# DaemonSet for the agent
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: labs-agent
spec:
  template:
    spec:
      containers:
        - name: labs-agent
          image: site24x7-labs-agent:latest
          env:
            - name: CHAOS_CONFIG_DIR
              value: /var/site24x7-labs/faults
          volumeMounts:
            - name: chaos-config
              mountPath: /var/site24x7-labs/faults
      volumes:
        - name: chaos-config
          hostPath:
            path: /var/site24x7-labs/faults
            type: DirectoryOrCreate
---
# Application Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
spec:
  template:
    spec:
      containers:
        - name: order-service
          image: your-org/order-service:latest
          env:
            - name: CHAOS_SDK_ENABLED
              value: "true"
            - name: CHAOS_SDK_APP_NAME
              value: order-service
          volumeMounts:
            - name: chaos-config
              mountPath: /var/site24x7-labs/faults
      volumes:
        - name: chaos-config
          hostPath:
            path: /var/site24x7-labs/faults
            type: DirectoryOrCreate
```

---

## How It Works

### End-to-end fault injection flow

1. **User creates/toggles a fault rule** in the Site24x7 Labs UI
2. **Labs Server** receives the API request, updates the database, and dispatches the config via gRPC
3. **Labs Agent** receives the config via the `ExperimentStream` with action `update_fault_config`
4. **Agent writes** the config as a JSON file to the shared volume: `/var/site24x7-labs/faults/{app_name}.json` (atomic write via temp file + rename)
5. **SDK's ConfigFileWatcher** goroutine detects the file change (via modification time check, every 2 seconds)
6. **ChaosEngine** parses the new rules and swaps the active rules list atomically (behind `sync.RWMutex`)
7. **Next incoming request/query**: the middleware or hook evaluates matching rules and applies the fault based on probability

### What InitChaos() does

When you call `chaos.InitChaos("order-service")`, the SDK:

1. **Creates a ChaosEngine** — resolves `app_name`, `config_dir`, and `enabled` from parameters or environment variables
2. **Starts the ConfigFileWatcher** goroutine — polls `{config_dir}/{app_name}.json` every 2 seconds via `time.Ticker`
3. **Starts the HeartbeatWriter** goroutine — writes `{app_name}.heartbeat.json` every 30 seconds (atomic write via temp + `os.Rename`)
4. **Returns `*ChaosInstance`** — holds the engine and background goroutines; call `ci.Shutdown()` on exit

You then wire up fault injectors yourself:

- `fault.HTTPMiddleware(engine)` — net/http middleware (or use gin/echo adapters)
- `fault.NewTransport(engine, http.DefaultTransport)` — outbound HTTP transport wrapper
- `fault.WrapDriver("postgres", pgDriver, engine)` — database/sql driver wrapper
- `fault.NewRedisHook(engine)` — go-redis v9 hook
- `fault.NewResourceFaultInjector(engine).Install()` — resource fault listener

### Thread-safety model

- `Engine.rules` is protected by `sync.RWMutex` — read operations (`FindMatchingRules`, `ShouldFire`) take an RLock; write operations (`UpdateRules`) take a full Lock
- Config update listeners are notified outside the write lock
- Resource fault injector uses `sync/atomic.Bool` for the one-active-at-a-time guard
- `ShouldFire()` uses `math/rand.Float64()` for probability checks

### Supported libraries

| Category | Integration Method | Libraries |
|---|---|---|
| HTTP Server | `http.Handler` middleware | net/http, chi, gorilla/mux, any `http.Handler`-compatible router |
| HTTP Server | Framework adapter | Gin (`gin.HandlerFunc`), Echo (`echo.MiddlewareFunc`) |
| HTTP Client | `http.RoundTripper` wrapper | `http.Client`, any library using `http.Transport` |
| Database | `database/sql/driver.Driver` wrapper | PostgreSQL (pgx, lib/pq), MySQL, any `database/sql` driver |
| Redis | `redis.Hook` interface | go-redis/redis/v9 |

---

## Advanced Usage

### Outbound HTTP Client faults

Wrap the `http.Client` transport with the chaos transport:

```go
client := &http.Client{
    Transport: fault.NewTransport(ci.Engine, http.DefaultTransport),
}
resp, err := client.Get("https://api.example.com/data")
```

### Database faults

Register the chaos driver wrapper before opening the database:

```go
import (
    "database/sql"
    "github.com/lib/pq"
    "github.com/site24x7/observe-labs/sdks/go/fault"
)

// Register wrapped driver (do this once, before sql.Open)
fault.WrapDriver("chaos-postgres", &pq.Driver{}, ci.Engine)

db, err := sql.Open("chaos-postgres", "postgres://localhost/mydb?sslmode=disable")
```

### Redis faults

Add the chaos hook to your go-redis client:

```go
import (
    "github.com/redis/go-redis/v9"
    "github.com/site24x7/observe-labs/sdks/go/fault"
)

rdb := redis.NewClient(&redis.Options{Addr: "localhost:6379"})
rdb.AddHook(fault.NewRedisHook(ci.Engine))
```

### Resource faults

Install the resource fault injector to trigger resource faults on config changes:

```go
injector := fault.NewResourceFaultInjector(ci.Engine)
injector.Install()
```

### Graceful shutdown

```go
ci, _ := chaos.InitChaos("order-service")
defer ci.Shutdown()

// Or handle signals manually:
sigCh := make(chan os.Signal, 1)
signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
<-sigCh
ci.Shutdown()
```

`Shutdown()` cancels the root context (stopping watcher + heartbeat goroutines), and is safe to call multiple times.

### Disabling the SDK

Set the environment variable:

```bash
export CHAOS_SDK_ENABLED=false
```

Or pass the option:

```go
ci, _ := chaos.InitChaos("order-service", chaos.WithEnabled(false))
```

When disabled, the SDK:
- Starts but the engine's `Enabled` flag is `false`
- `FindMatchingRules()` returns empty slices
- No faults are ever injected
- Config file watcher and heartbeat writer still run (so the service remains discoverable)

---

## Troubleshooting

### SDK not picking up fault rules

1. **Check the config file exists**:
   ```bash
   docker exec <container> ls -la /var/site24x7-labs/faults/
   ```
   You should see `{app_name}.json`. If not, the agent hasn't received the config yet.

2. **Check the config file contents**:
   ```bash
   docker exec <container> cat /var/site24x7-labs/faults/order-service.json
   ```
   Verify the rules array is non-empty and rules have `"enabled": true`.

3. **Check `CHAOS_SDK_APP_NAME` matches**: The app name must exactly match the `app_name` registered in the Labs UI. The config filename is `{app_name}.json`.

4. **Check volume mount**: Both the agent and your application must mount the same volume at the same path.

5. **Check logs**: The SDK logs to Go's `log` package with a `[chaos-sdk]` prefix. Look for:
   - `Chaos SDK initialized for net-http app "order-service"` — SDK initialized
   - `ConfigFileWatcher started` — watcher is running
   - `Config file changed, loaded N rules` — rules loaded successfully

### Faults not firing

1. **Check probability**: A probability of `0.3` means only 30% of requests will be affected. Set to `1.0` for guaranteed activation during testing.

2. **Check URL pattern**: If a URL pattern is set, it must match the request path. An empty pattern matches all requests.

3. **Check fault rule is enabled**: The `enabled` flag in the config file must be `true`.

4. **Check `CHAOS_SDK_ENABLED`**: If set to `false`, the entire SDK is disabled.

### Database faults not working

1. **Register the wrapped driver**: Database faults require `fault.WrapDriver()` to be called before `sql.Open()`.

2. **Use the chaos driver name**: When opening the database, use the driver name you registered (e.g., `"chaos-postgres"`), not the original driver name.

3. **Connection pool drain**: This fault calls `db.Conn(ctx)` repeatedly. It works with Go's standard `sql.DB` connection pool.

### Redis faults not working

1. **Ensure go-redis v9 is installed**: `go get github.com/redis/go-redis/v9`

2. **Add the hook**: Call `rdb.AddHook(fault.NewRedisHook(ci.Engine))` after creating the client.

3. **Check logs**: Look for `[chaos-sdk] RedisHook installed`.

### Outbound HTTP faults not working

1. **Wrap the transport**: Set `client.Transport = fault.NewTransport(engine, http.DefaultTransport)`.

2. **Direct socket calls**: The transport wrapper only intercepts calls through `http.Client`. Direct `net.Dial`, `net.Conn`, or raw TCP calls are not intercepted.

### Config file not updating

1. **Check agent connectivity**: The agent must be connected to the Labs server via gRPC. Check agent logs for connection errors.

2. **Check agent logs**: Look for `Writing fault config for app:` messages to confirm the agent is receiving and writing configs.

### Performance impact

- **Config file polling**: Negligible. One `os.Stat()` syscall every 2 seconds, file read only when mtime changes.
- **HTTP fault evaluation**: One slice scan per request (typically 0-5 rules). Sub-microsecond.
- **RoundTripper overhead**: One function call indirection per outbound request. Negligible compared to actual network I/O.
- **No network calls**: The SDK never makes HTTP/gRPC calls, so there is zero network overhead and zero APM noise.
