# Site24x7 Labs Chaos SDK for Go

Inject realistic application-level faults into Go microservices using Gin, Echo, or net/http. Faults are controlled from the Site24x7 Labs UI, injected via this SDK embedded in the target app, and captured by Site24x7 APM to showcase its monitoring capabilities.

## Quick Start

### Install

> SDKs are shipped only in [site24x7/demo-apps](https://github.com/site24x7/demo-apps) under `chaos-libs/` (see `chaos-libs/README.md` there); they are not published to a Go module proxy or tags. Paths below assume the app sits at `Applications/<app>/services/<svc>/` in demo-apps.

Requires Go 1.25+. In `go.mod`:

```go
require github.com/site24x7/observe-labs/sdks/go v<version>

replace github.com/site24x7/observe-labs/sdks/go => ../../../../chaos-libs/go
```

### Initialize

**Gin:**

```go
import (
    chaos "github.com/site24x7/observe-labs/sdks/go"
    ginmw "github.com/site24x7/observe-labs/sdks/go/gin"
)

func main() {
    sdk := chaos.New(chaos.Options{
        AppName:   "search-service",
        ConfigDir: "/var/site24x7-labs/faults",
    })
    defer sdk.Close()

    r := gin.Default()
    r.Use(ginmw.ChaosMiddleware(sdk.Engine()))
    r.Run(":8083")
}
```

**Echo:**

```go
import (
    chaos "github.com/site24x7/observe-labs/sdks/go"
    echomw "github.com/site24x7/observe-labs/sdks/go/echo"
)

func main() {
    sdk := chaos.New(chaos.Options{
        AppName:   "search-service",
        ConfigDir: "/var/site24x7-labs/faults",
    })
    defer sdk.Close()

    e := echo.New()
    e.Use(echomw.ChaosMiddleware(sdk.Engine()))
    e.Start(":8083")
}
```

### Set environment variables

```bash
export CHAOS_SDK_ENABLED=true
export CHAOS_SDK_APP_NAME=search-service
export CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults
```

### Mount the shared volume

In Docker Compose or Kubernetes, mount the agent's config directory:

```yaml
services:
  search-service:
    volumes:
      - chaos_config:/var/site24x7-labs/faults:ro
```

## Supported Fault Types (19)

| # | Fault Type | Category | Description |
|---|---|---|---|
| 1 | `http_exception` | Inbound HTTP | Return the mapped Go error as a 500 response |
| 2 | `http_latency` | Inbound HTTP | Delay before the request is handled |
| 3 | `http_error_response` | Inbound HTTP | Return a static error status + body |
| 4 | `http_connection_reset` | Inbound HTTP | Hijack and close the connection |
| 5 | `http_slow_body` | Inbound HTTP | Stream a response body with inter-chunk delays |
| 6 | `http_client_latency` | Outbound HTTP | Add latency to outbound HTTP calls |
| 7 | `http_client_exception` | Outbound HTTP | Return an error instead of making the call |
| 8 | `http_client_error_response` | Outbound HTTP | Return a fake error response |
| 9 | `jdbc_exception` | Database | Return a database error before the query |
| 10 | `jdbc_latency` | Database | Delay before the query executes |
| 11 | `jdbc_connection_pool_drain` | Database | Acquire and hold connections |
| 12 | `redis_exception` | Redis | Return a mapped error before the command runs |
| 13 | `redis_latency` | Redis | Delay before the command runs |
| 14 | `thread_pool_exhaustion` | Resource | Leaked goroutines blocked on a channel |
| 15 | `memory_pressure` | Resource | Allocate []byte slices and hold them |
| 16 | `cpu_burn` | Resource | LockOSThread + tight math loops |
| 17 | `gc_pressure` | Resource | Rapid short-lived allocations |
| 18 | `thread_deadlock` | Resource | Goroutines blocked on channel with no writer |
| 19 | `disk_fill` | Resource | Write temp files to consume disk space |

## Documentation

See [`docs/integration-guide.md`](docs/integration-guide.md) for the full integration guide.

## Requirements

- Go >= 1.21
- Gin >= 1.9 or Echo >= 4.11 (optional — net/http works directly)
- Access to the Site24x7 Labs agent shared volume

## License

MIT
