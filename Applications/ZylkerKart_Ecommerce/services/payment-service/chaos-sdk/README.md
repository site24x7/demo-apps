# Site24x7 Labs Chaos SDK for Python

Inject realistic application-level faults into Python/Flask and Python/FastAPI microservices during Site24x7 demos. Faults are controlled from the Site24x7 Labs UI, injected via this SDK embedded in the target app, and captured by Site24x7 APM to showcase its monitoring capabilities.

## Quick Start

### Install

```bash
# Flask app
pip install site24x7-chaos[flask]

# FastAPI app
pip install site24x7-chaos[fastapi]

# All optional dependencies
pip install site24x7-chaos[all]
```

### Initialize (one line)

**Flask:**

```python
from flask import Flask
from site24x7_chaos.flask import init_chaos

app = Flask(__name__)
init_chaos(app)
```

**FastAPI:**

```python
from fastapi import FastAPI
from site24x7_chaos.fastapi import init_chaos

app = FastAPI()
init_chaos(app)
```

### Set environment variables

```bash
export CHAOS_SDK_ENABLED=true
export CHAOS_SDK_APP_NAME=order-service
export CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults
```

### Mount the shared volume

In Docker Compose, add a shared volume so the agent can write config files and the SDK can read them:

```yaml
services:
  order-service:
    volumes:
      - chaos_config:/var/site24x7-labs/faults:ro
```

That's it. No other code changes required.

## Supported Fault Types (19)

| # | Fault Type | Category | Description |
|---|---|---|---|
| 1 | `http_exception` | Inbound HTTP | Raise a mapped Python exception |
| 2 | `http_latency` | Inbound HTTP | Add artificial latency to requests |
| 3 | `http_error_response` | Inbound HTTP | Return a static error response |
| 4 | `http_connection_reset` | Inbound HTTP | Abort the socket connection |
| 5 | `http_slow_body` | Inbound HTTP | Stream a response body with inter-chunk delays |
| 6 | `http_client_latency` | Outbound HTTP | Add latency to outbound requests/httpx calls |
| 7 | `http_client_exception` | Outbound HTTP | Raise an exception on outbound calls |
| 8 | `http_client_error_response` | Outbound HTTP | Return a fake error response from outbound calls |
| 9 | `jdbc_exception` | Database | Raise a SQLAlchemy exception before queries |
| 10 | `jdbc_latency` | Database | Add latency before queries |
| 11 | `jdbc_connection_pool_drain` | Database | Hold connections from the pool |
| 12 | `redis_exception` | Redis | Raise a redis-py exception on commands |
| 13 | `redis_latency` | Redis | Add latency before Redis commands |
| 14 | `thread_pool_exhaustion` | Resource | Spawn busy-sleeping threads |
| 15 | `memory_pressure` | Resource | Allocate large bytearrays on the heap |
| 16 | `cpu_burn` | Resource | Tight math loops across threads |
| 17 | `gc_pressure` | Resource | Rapid short-lived allocations to stress the GC |
| 18 | `thread_deadlock` | Resource | Two threads that deadlock on locks |
| 19 | `disk_fill` | Resource | Write temp files to consume disk space |

## Optional Dependencies

| Extra | Libraries | Purpose |
|---|---|---|
| `flask` | Flask >= 2.0 | Flask middleware integration |
| `fastapi` | FastAPI >= 0.68, Starlette >= 0.14 | FastAPI/ASGI middleware integration |
| `sqlalchemy` | SQLAlchemy >= 1.4 | Database fault injection |
| `redis` | redis-py >= 4.0 | Redis fault injection |
| `requests` | requests >= 2.20 | Outbound HTTP fault injection (requests) |
| `httpx` | httpx >= 0.23 | Outbound HTTP fault injection (httpx) |
| `all` | All of the above | Everything |

## Documentation

See [`docs/integration-guide.md`](docs/integration-guide.md) for the full integration guide including:

- Architecture overview and how faults flow from UI to SDK
- Detailed config for all 19 fault types
- Docker and Kubernetes deployment examples
- `init_chaos()` parameter reference
- Troubleshooting guide

## Requirements

- Python >= 3.9
- Flask >= 2.0 or FastAPI >= 0.68
- Access to the Site24x7 Labs agent shared volume
