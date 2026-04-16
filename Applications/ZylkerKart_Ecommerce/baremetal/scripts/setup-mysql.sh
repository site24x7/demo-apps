#!/usr/bin/env bash
# =============================================================================
# ZylkerKart — MySQL Database Setup
# =============================================================================
# Creates the 5 ZylkerKart databases, loads schema, and seeds data.
# Requires MySQL 8.0+ to be already installed and running.
#
# Usage:
#   tar xzf zylkerkart-mysql-<version>.tar.gz
#   cd zylkerkart-mysql-<version>
#   cp config/mysql.env.example mysql.env
#   nano mysql.env   # set your root password
#   sudo ./setup-mysql.sh
#
# Databases created:
#   db_product  — Product catalog (9 tables)
#   db_order    — Orders and cart (3 tables)
#   db_search   — Search index (1 table)
#   db_payment  — Payment transactions (1 table)
#   db_auth     — Users and auth tokens (3 tables)
# =============================================================================

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[mysql-setup]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
err()   { echo -e "${RED}[error]${NC} $*" >&2; }
info()  { echo -e "${BLUE}[info]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Load configuration ──────────────────────────────────────────────────────
ENV_FILE="$SCRIPT_DIR/mysql.env"
if [[ ! -f "$ENV_FILE" ]]; then
    # Also check config/ subdirectory
    if [[ -f "$SCRIPT_DIR/config/mysql.env" ]]; then
        ENV_FILE="$SCRIPT_DIR/config/mysql.env"
    else
        err "Configuration file not found."
        err "Copy the template and edit it:"
        err "  cp config/mysql.env.example mysql.env"
        err "  nano mysql.env"
        exit 1
    fi
fi

source "$ENV_FILE"

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:?mysql.env must define MYSQL_ROOT_PASSWORD}"
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"

# Optional app user
APP_DB_USER="${APP_DB_USER:-}"
APP_DB_PASSWORD="${APP_DB_PASSWORD:-}"

# ── Check prerequisites ─────────────────────────────────────────────────────
if ! command -v mysql &>/dev/null; then
    err "'mysql' client not found in PATH"
    err "Please install MySQL 8.0 client tools."
    exit 1
fi

MYSQL_CMD="mysql -h${MYSQL_HOST} -P${MYSQL_PORT} -uroot -p${MYSQL_ROOT_PASSWORD}"

# Test connection
log "Testing MySQL connection..."
if ! $MYSQL_CMD -e "SELECT 1" &>/dev/null; then
    err "Cannot connect to MySQL at ${MYSQL_HOST}:${MYSQL_PORT}"
    err "Check that MySQL is running and the root password is correct."
    exit 1
fi

MYSQL_VERSION=$($MYSQL_CMD -N -e "SELECT VERSION()" 2>/dev/null)
info "Connected to MySQL ${MYSQL_VERSION} at ${MYSQL_HOST}:${MYSQL_PORT}"

# ── Check for SQL files ─────────────────────────────────────────────────────
SQL_DIR="$SCRIPT_DIR/sql"
if [[ ! -d "$SQL_DIR" ]]; then
    err "sql/ directory not found in $SCRIPT_DIR"
    exit 1
fi

SCHEMA_FILE="$SQL_DIR/01-schema.sql"
SEED_FILE="$SQL_DIR/02-seed-data.sql"

if [[ ! -f "$SCHEMA_FILE" ]]; then
    err "Schema file not found: $SCHEMA_FILE"
    exit 1
fi

# ── Create databases ────────────────────────────────────────────────────────
DATABASES=(db_product db_order db_search db_payment db_auth)

log "Creating databases..."
for db in "${DATABASES[@]}"; do
    $MYSQL_CMD -e "CREATE DATABASE IF NOT EXISTS \`${db}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
    info "Database '${db}' — OK"
done

# ── Load schema ─────────────────────────────────────────────────────────────
log "Loading schema from 01-schema.sql..."
$MYSQL_CMD < "$SCHEMA_FILE" 2>/dev/null
info "Schema loaded successfully"

# ── Load seed data ──────────────────────────────────────────────────────────
if [[ -f "$SEED_FILE" ]]; then
    log "Loading seed data from 02-seed-data.sql..."
    $MYSQL_CMD < "$SEED_FILE" 2>/dev/null
    info "Seed data loaded successfully"
else
    warn "No seed data file found (02-seed-data.sql) — skipping"
fi

# ── Create application user (optional) ──────────────────────────────────────
if [[ -n "$APP_DB_USER" && -n "$APP_DB_PASSWORD" ]]; then
    log "Creating application user '${APP_DB_USER}'..."
    $MYSQL_CMD -e "
        CREATE USER IF NOT EXISTS '${APP_DB_USER}'@'%' IDENTIFIED BY '${APP_DB_PASSWORD}';
    " 2>/dev/null

    for db in "${DATABASES[@]}"; do
        $MYSQL_CMD -e "GRANT ALL PRIVILEGES ON \`${db}\`.* TO '${APP_DB_USER}'@'%';" 2>/dev/null
    done

    $MYSQL_CMD -e "FLUSH PRIVILEGES;" 2>/dev/null
    info "User '${APP_DB_USER}' created with grants on all 5 databases"
else
    info "No APP_DB_USER set — services will connect as root"
fi

# ── Verify ──────────────────────────────────────────────────────────────────
log "Verifying setup..."
echo ""
echo "  Database          | Tables"
echo "  ──────────────────|────────"
for db in "${DATABASES[@]}"; do
    count=$($MYSQL_CMD -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${db}';" 2>/dev/null)
    printf "  %-18s | %s tables\n" "$db" "$count"
done
echo ""

# ── Summary ─────────────────────────────────────────────────────────────────
echo "============================================================================="
echo -e "${GREEN} ZylkerKart MySQL setup completed successfully!${NC}"
echo "============================================================================="
echo ""
echo "  Host:       ${MYSQL_HOST}:${MYSQL_PORT}"
echo "  Databases:  ${DATABASES[*]}"
if [[ -n "$APP_DB_USER" ]]; then
    echo "  App user:   ${APP_DB_USER}"
fi
echo ""
echo "  Connection string examples:"
echo "  ──────────────────────────"
echo "  JDBC:   jdbc:mysql://${MYSQL_HOST}:${MYSQL_PORT}/db_product?useSSL=false&allowPublicKeyRetrieval=true"
echo "  Node:   mysql://${MYSQL_HOST}:${MYSQL_PORT}/db_order"
echo "  Go:     root:****@tcp(${MYSQL_HOST}:${MYSQL_PORT})/db_search"
echo "  Python: mysql+connector://${MYSQL_HOST}:${MYSQL_PORT}/db_payment"
echo ""
echo "============================================================================="
