# ZylkerKart — Bare Metal Deployment Guide

Deploy ZylkerKart microservices on bare metal Linux servers using universal tar.gz artifacts from GitHub Releases.

## Architecture Overview

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Server 1    │     │  Server 2        │     │  Server 3        │
│  MySQL 8.0   │     │  Redis 7.x       │     │  Auth Service    │
│  Port: 3306  │     │  Port: 6379      │     │  Port: 8085      │
│              │     │                  │     │  (.NET 8)        │
└──────┬───────┘     └──────┬───────────┘     └──────────────────┘
       │                    │
       │    ┌───────────────┴──────────────────────┐
       │    │                                      │
┌──────┴────┴──┐     ┌──────────────────┐     ┌───┴──────────────┐
│  Server 4    │     │  Server 5        │     │  Server 6        │
│  Product Svc │     │  Order Service   │     │  Search Service  │
│  Port: 8081  │     │  Port: 8082      │     │  Port: 8083      │
│  (Java 17)   │     │  (Node.js 18)    │     │  (Go static bin) │
└──────────────┘     └──────────────────┘     └──────────────────┘

┌──────────────┐     ┌──────────────────┐
│  Server 7    │     │  Server 8        │
│  Payment Svc │     │  Storefront BFF  │
│  Port: 8084  │     │  Port: 80        │
│  (Python 3.11)│    │  (Java 17)       │
└──────────────┘     └──────────────────┘
```

## Artifacts

Each release on GitHub contains 8 tar.gz files:

| Artifact | Contents | Runtime Required |
|---|---|---|
| `zylkerkart-storefront-<ver>-linux-amd64.tar.gz` | Fat JAR (`app.jar`) | JRE 17 |
| `zylkerkart-product-service-<ver>-linux-amd64.tar.gz` | Fat JAR (`app.jar`) | JRE 17 |
| `zylkerkart-order-service-<ver>-linux-amd64.tar.gz` | Source + `node_modules/` | Node.js 18 |
| `zylkerkart-search-service-<ver>-linux-amd64.tar.gz` | Static binary | None |
| `zylkerkart-payment-service-<ver>-linux-amd64.tar.gz` | Source + `requirements.txt` | Python 3.11 + pip |
| `zylkerkart-auth-service-<ver>-linux-amd64.tar.gz` | Published DLLs | dotnet-runtime-8.0 |
| `zylkerkart-mysql-<ver>.tar.gz` | SQL schema + seed data | MySQL 8.0 (pre-installed) |
| `zylkerkart-redis-<ver>.tar.gz` | Config + systemd unit | Redis 7.x (pre-installed) |

## Prerequisites

Install the required runtime on each server **before** running the install scripts.
The scripts check for prerequisites but do **not** install them — this keeps them OS-agnostic.

| Server | Install (Ubuntu/Debian example) | Install (RHEL/Amazon Linux example) |
|---|---|---|
| MySQL | `apt install mysql-server-8.0` | `yum install mysql-community-server` |
| Redis | `apt install redis-server` | `yum install redis` |
| Storefront | `apt install temurin-17-jre` | `yum install java-17-amazon-corretto` |
| Product Service | `apt install temurin-17-jre` | `yum install java-17-amazon-corretto` |
| Order Service | Install Node.js 18 via [NodeSource](https://github.com/nodesource/distributions) | Same |
| Search Service | **None** (static binary) | **None** |
| Payment Service | `apt install python3.11 python3.11-venv python3-pip` | `yum install python3.11 python3.11-pip` |
| Auth Service | Install [.NET 8 runtime](https://dotnet.microsoft.com/download/dotnet/8.0) | Same |

## Deployment Order

Deploy infrastructure first, then services (backend → frontend):

```
1. MySQL        →  setup-mysql.sh
2. Redis        →  setup-redis.sh
3. Auth Service →  install.sh
4. Product Service → install.sh
5. Search Service  → install.sh
6. Payment Service → install.sh
7. Order Service   → install.sh
8. Storefront      → install.sh
```

## Step-by-Step Deployment

### 1. Deploy MySQL (Server 1)

```bash
# Download
VERSION=v1.0.0
curl -LO https://github.com/site24x7/demo-apps/releases/download/${VERSION}/zylkerkart-mysql-${VERSION}.tar.gz

# Extract
tar xzf zylkerkart-mysql-${VERSION}.tar.gz
cd zylkerkart-mysql-${VERSION}

# Configure
cp config/mysql.env.example mysql.env
nano mysql.env
# Set: MYSQL_ROOT_PASSWORD, MYSQL_HOST (localhost if running locally)

# Run setup
sudo ./setup-mysql.sh
```

This creates 5 databases (`db_product`, `db_order`, `db_search`, `db_payment`, `db_auth`),
loads the schema (17 tables), and seeds product data.

### 2. Deploy Redis (Server 2)

```bash
VERSION=v1.0.0
curl -LO https://github.com/site24x7/demo-apps/releases/download/${VERSION}/zylkerkart-redis-${VERSION}.tar.gz
tar xzf zylkerkart-redis-${VERSION}.tar.gz
cd zylkerkart-redis-${VERSION}

sudo ./setup-redis.sh

# Start Redis
sudo systemctl start zylkerkart-redis

# Verify
redis-cli ping   # → PONG
```

### 3. Deploy a Microservice (Servers 3–8)

All 6 services follow the same pattern:

```bash
# Download (example: auth-service)
VERSION=v1.0.0
SERVICE=auth-service
curl -LO https://github.com/site24x7/demo-apps/releases/download/${VERSION}/zylkerkart-${SERVICE}-${VERSION}-linux-amd64.tar.gz

# Extract
tar xzf zylkerkart-${SERVICE}-${VERSION}-linux-amd64.tar.gz
cd zylkerkart-${SERVICE}-${VERSION}-linux-amd64

# Install (creates user, copies files, enables systemd service)
sudo ./install.sh

# Configure — IMPORTANT: set real server IPs
sudo nano /etc/zylkerkart/${SERVICE}.env
# Replace MYSQL_SERVER_IP, REDIS_SERVER_IP, etc. with actual IPs

# Start
sudo systemctl start zylkerkart-${SERVICE}

# Verify
sudo systemctl status zylkerkart-${SERVICE}
sudo journalctl -u zylkerkart-${SERVICE} -f
```

### 4. Verify the Full Stack

Once all services are running, test from the storefront server:

```bash
# Health checks
curl http://localhost:80/health            # Storefront
curl http://PRODUCT_IP:8081/health         # Product Service
curl http://ORDER_IP:8082/health           # Order Service
curl http://SEARCH_IP:8083/health          # Search Service
curl http://PAYMENT_IP:8084/health         # Payment Service
curl http://AUTH_IP:8085/health            # Auth Service

# Test storefront UI
curl -s http://STOREFRONT_IP/ | head -20
```

## Configuration Reference

### Environment Files

All service configs live in `/etc/zylkerkart/`:

```
/etc/zylkerkart/
├── storefront.env
├── product-service.env
├── order-service.env
├── search-service.env
├── payment-service.env
├── auth-service.env
└── redis.conf
```

### Key Configuration: Service Discovery

Since there's no DNS/service mesh on bare metal, services find each other via environment variables.
**You must replace placeholder IPs with real server IPs** in each `.env` file.

**Storefront** (`/etc/zylkerkart/storefront.env`):
```env
PRODUCT_SERVICE_URL=http://10.0.1.4:8081
ORDER_SERVICE_URL=http://10.0.1.5:8082
SEARCH_SERVICE_URL=http://10.0.1.6:8083
PAYMENT_SERVICE_URL=http://10.0.1.7:8084
AUTH_SERVICE_URL=http://10.0.1.3:8085
REDIS_HOST=10.0.1.2
```

**Backend services** (product, order, search, payment, auth):
```env
DB_HOST=10.0.1.1          # or MYSQL_HOST for Java services
REDIS_HOST=10.0.1.2
```

**Order Service** also needs:
```env
PAYMENT_SERVICE_URL=http://10.0.1.7:8084
AUTH_SERVICE_URL=http://10.0.1.3:8085
```

### Service Dependencies

```
Storefront ──→ Product, Order, Search, Payment, Auth, Redis (sessions)
Order      ──→ MySQL (db_order), Redis (cart), Payment (HTTP), Auth (HTTP)
Product    ──→ MySQL (db_product), Redis (cache)
Search     ──→ MySQL (db_search), Redis (cache)
Payment    ──→ MySQL (db_payment)
Auth       ──→ MySQL (db_auth)
```

## Managing Services

### systemd Commands

```bash
# Start / Stop / Restart
sudo systemctl start zylkerkart-storefront
sudo systemctl stop zylkerkart-storefront
sudo systemctl restart zylkerkart-storefront

# Status
sudo systemctl status zylkerkart-storefront

# Logs (real-time)
sudo journalctl -u zylkerkart-storefront -f

# Logs (last 100 lines)
sudo journalctl -u zylkerkart-storefront -n 100

# Enable / Disable auto-start on boot
sudo systemctl enable zylkerkart-storefront
sudo systemctl disable zylkerkart-storefront
```

### File Locations

| Path | Purpose |
|---|---|
| `/opt/zylkerkart/<service>/` | Application binaries/source |
| `/etc/zylkerkart/<service>.env` | Environment configuration |
| `/etc/systemd/system/zylkerkart-<service>.service` | Systemd unit file |
| `/var/site24x7-labs/faults/` | Chaos SDK fault config directory |

### Upgrading a Service

```bash
# Download new version
curl -LO https://github.com/site24x7/demo-apps/releases/download/v1.1.0/zylkerkart-storefront-v1.1.0-linux-amd64.tar.gz

# Extract and re-run install (it stops the service, overwrites files, preserves your .env)
tar xzf zylkerkart-storefront-v1.1.0-linux-amd64.tar.gz
cd zylkerkart-storefront-v1.1.0-linux-amd64
sudo ./install.sh

# Start the upgraded service
sudo systemctl start zylkerkart-storefront
```

The `install.sh` script **never overwrites** your existing `/etc/zylkerkart/<service>.env` — your configuration is preserved across upgrades.

## Chaos SDK (Optional)

Each service includes the Site24x7 Labs Chaos SDK. To enable it, set in the service's `.env` file:

```env
CHAOS_SDK_ENABLED=true
CHAOS_SDK_APP_NAME=storefront
CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults
```

The fault config directory `/var/site24x7-labs/faults/` is created by `install.sh` and owned by the `zylkerkart` user.

## CI/CD: How Releases Are Built

The GitHub Actions workflow (`.github/workflows/zylkerkart-baremetal.yml`) runs when you push a version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

This triggers 8 parallel build jobs:

1. **Java services** — Maven builds fat JARs with `mvn package`
2. **Node.js service** — `npm install --omit=dev` bundles `node_modules/`
3. **Go service** — `CGO_ENABLED=0 go build` produces a static binary
4. **Python service** — Packages source + `requirements.txt` (venv created on target)
5. **.NET service** — `dotnet publish` produces framework-dependent DLLs
6. **MySQL** — Generates seed SQL from CSV via `generate_seed_sql.py`
7. **Redis** — Packages config files only

All 8 tarballs are uploaded to a GitHub Release automatically.

## Troubleshooting

### Service won't start

```bash
# Check logs for the specific error
sudo journalctl -u zylkerkart-<service> --no-pager -n 50

# Common issues:
# - Wrong server IPs in .env file
# - MySQL not reachable (check firewall)
# - Missing runtime (java/node/python/dotnet not installed)
# - Port already in use
```

### Database connection refused

```bash
# From the service's server, test MySQL connectivity:
mysql -h MYSQL_SERVER_IP -P 3306 -u root -p -e "SELECT 1"

# Check MySQL is listening on all interfaces (not just localhost):
# In /etc/mysql/mysql.conf.d/mysqld.cnf:
#   bind-address = 0.0.0.0
```

### Redis connection refused

```bash
# Test from service server:
redis-cli -h REDIS_SERVER_IP ping

# Check redis.conf has: bind 0.0.0.0
# Check firewall allows port 6379
```

### Payment service Python venv issues

```bash
# The install.sh creates a venv and installs deps (requires internet)
# If pip install failed, retry manually:
sudo -u zylkerkart /opt/zylkerkart/payment-service/venv/bin/pip install -r /opt/zylkerkart/payment-service/requirements.txt
```
