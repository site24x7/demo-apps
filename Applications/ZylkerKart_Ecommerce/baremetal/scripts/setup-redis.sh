#!/usr/bin/env bash
# =============================================================================
# ZylkerKart — Redis Setup
# =============================================================================
# Applies the ZylkerKart Redis configuration to an existing Redis installation.
# Requires redis-server 7.x to be already installed.
#
# Usage:
#   tar xzf zylkerkart-redis-<version>.tar.gz
#   cd zylkerkart-redis-<version>
#   sudo ./setup-redis.sh
#
# What this does:
#   1. Backs up existing redis.conf
#   2. Copies ZylkerKart redis.conf to /etc/zylkerkart/redis.conf
#   3. Optionally installs a dedicated systemd unit
#   4. Verifies Redis is responding
# =============================================================================

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[redis-setup]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
err()   { echo -e "${RED}[error]${NC} $*" >&2; }
info()  { echo -e "${BLUE}[info]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Pre-flight checks ───────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (use sudo)"
    exit 1
fi

if ! command -v redis-server &>/dev/null; then
    err "'redis-server' not found in PATH"
    err "Please install Redis 7.x before running this script."
    exit 1
fi

REDIS_VERSION=$(redis-server --version | grep -oP 'v=\K[0-9.]+' 2>/dev/null || redis-server --version)
info "Found Redis: ${REDIS_VERSION}"

# ── Configuration ────────────────────────────────────────────────────────────
CONFIG_DIR="/etc/zylkerkart"
CONFIG_FILE="${CONFIG_DIR}/redis.conf"
DATA_DIR="/var/lib/redis"
SYSTEMD_DIR="/etc/systemd/system"

mkdir -p "$CONFIG_DIR"
mkdir -p "$DATA_DIR"

# ── Install configuration ───────────────────────────────────────────────────
if [[ -f "$SCRIPT_DIR/config/redis.conf" ]]; then
    if [[ -f "$CONFIG_FILE" ]]; then
        BACKUP="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
        warn "Existing config found — backing up to ${BACKUP}"
        cp "$CONFIG_FILE" "$BACKUP"
    fi

    cp "$SCRIPT_DIR/config/redis.conf" "$CONFIG_FILE"
    log "Installed Redis config to ${CONFIG_FILE}"
else
    err "config/redis.conf not found in tarball"
    exit 1
fi

# ── Set data directory permissions ───────────────────────────────────────────
# Try to use 'redis' user if it exists (created by most package managers)
if id -u redis &>/dev/null; then
    chown -R redis:redis "$DATA_DIR"
    info "Data directory ${DATA_DIR} owned by redis user"
else
    warn "No 'redis' user found — data dir permissions unchanged"
fi

# ── Install systemd unit (optional) ─────────────────────────────────────────
if [[ -f "$SCRIPT_DIR/systemd/zylkerkart-redis.service" ]]; then
    echo ""
    info "A custom ZylkerKart Redis systemd unit is available."
    info "Your distro may already have a redis-server.service or redis.service."
    echo ""

    # Check for existing Redis systemd units
    EXISTING_UNIT=""
    for unit in redis-server redis redis-sentinel; do
        if systemctl list-unit-files "${unit}.service" &>/dev/null 2>&1; then
            if systemctl list-unit-files "${unit}.service" | grep -q "${unit}.service"; then
                EXISTING_UNIT="${unit}.service"
                break
            fi
        fi
    done

    if [[ -n "$EXISTING_UNIT" ]]; then
        info "Found existing Redis unit: ${EXISTING_UNIT}"
        info "You can either:"
        info "  a) Reconfigure ${EXISTING_UNIT} to use ${CONFIG_FILE}"
        info "  b) Disable ${EXISTING_UNIT} and use the ZylkerKart unit instead"
        warn "Installing ZylkerKart Redis unit (you may need to disable ${EXISTING_UNIT})"
    fi

    cp "$SCRIPT_DIR/systemd/zylkerkart-redis.service" "${SYSTEMD_DIR}/"
    systemctl daemon-reload
    systemctl enable zylkerkart-redis.service
    log "Installed and enabled zylkerkart-redis.service"
fi

# ── Verify Redis ─────────────────────────────────────────────────────────────
if command -v redis-cli &>/dev/null; then
    # Try to ping Redis (might not be running yet with our config)
    if redis-cli ping &>/dev/null 2>&1; then
        PONG=$(redis-cli ping 2>/dev/null)
        info "Redis is responding: ${PONG}"
    else
        info "Redis not currently running (will start when you start the service)"
    fi
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "============================================================================="
echo -e "${GREEN} ZylkerKart Redis setup completed!${NC}"
echo "============================================================================="
echo ""
echo "  Config file:  ${CONFIG_FILE}"
echo "  Data dir:     ${DATA_DIR}"
echo "  Port:         6379"
echo "  Max memory:   256mb (allkeys-lru eviction)"
echo ""
echo "  Next steps:"
echo "  ────────────"
echo "  1. Review the config if needed:"
echo "     sudo nano ${CONFIG_FILE}"
echo ""
echo "  2. Start Redis:"
echo "     sudo systemctl start zylkerkart-redis"
echo "     # or restart your distro's Redis unit with the new config"
echo ""
echo "  3. Verify:"
echo "     redis-cli ping"
echo ""
echo "============================================================================="
