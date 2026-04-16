#!/usr/bin/env bash
# =============================================================================
# ZylkerKart — Universal Bare Metal Service Installer
# =============================================================================
# Installs a ZylkerKart service from its release tarball to the local system.
# Works on any Linux distribution with systemd.
#
# Usage:
#   tar xzf zylkerkart-<service>-<version>-linux-amd64.tar.gz
#   cd zylkerkart-<service>-<version>-linux-amd64
#   sudo ./install.sh
#
# The script reads a 'manifest' file in the same directory to determine
# which service to install and what prerequisites are needed.
#
# Supports: fresh install + upgrade (stops service, overwrites files, restarts)
# =============================================================================

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log()   { echo -e "${GREEN}[install]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
err()   { echo -e "${RED}[error]${NC} $*" >&2; }
info()  { echo -e "${BLUE}[info]${NC} $*"; }

# ── Pre-flight checks ───────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (use sudo)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/manifest" ]]; then
    err "manifest file not found in $SCRIPT_DIR"
    err "This script must be run from inside an extracted ZylkerKart tarball."
    exit 1
fi

# ── Read manifest ────────────────────────────────────────────────────────────
source "$SCRIPT_DIR/manifest"

# Required manifest variables
: "${SERVICE_NAME:?manifest must define SERVICE_NAME}"
: "${SERVICE_TYPE:?manifest must define SERVICE_TYPE}"
: "${SERVICE_PORT:?manifest must define SERVICE_PORT}"

INSTALL_DIR="/opt/zylkerkart/${SERVICE_NAME}"
CONFIG_DIR="/etc/zylkerkart"
SYSTEMD_DIR="/etc/systemd/system"
CHAOS_DIR="/var/site24x7-labs/faults"
UNIT_NAME="zylkerkart-${SERVICE_NAME}"
ENV_FILE="${CONFIG_DIR}/${SERVICE_NAME}.env"

log "Installing ZylkerKart ${SERVICE_NAME} (type=${SERVICE_TYPE}, port=${SERVICE_PORT})"

# ── Check prerequisites ─────────────────────────────────────────────────────
check_prerequisite() {
    local cmd="$1"
    local name="$2"
    local version_flag="${3:---version}"

    if ! command -v "$cmd" &>/dev/null; then
        err "Required: ${name} — '${cmd}' not found in PATH"
        err "Please install ${name} before running this script."
        return 1
    fi

    local version
    version=$("$cmd" "$version_flag" 2>&1 | head -1) || true
    info "Found ${name}: ${version}"
    return 0
}

prereq_ok=true
case "$SERVICE_TYPE" in
    java)
        check_prerequisite java "Eclipse Temurin JRE 17+" "-version" || prereq_ok=false
        ;;
    nodejs)
        check_prerequisite node "Node.js 18+" "--version" || prereq_ok=false
        ;;
    go)
        # Go services are static binaries — no runtime needed
        info "Go static binary — no runtime prerequisites"
        ;;
    python)
        check_prerequisite python3 "Python 3.11+" "--version" || prereq_ok=false
        check_prerequisite pip3 "pip" "--version" || prereq_ok=false
        ;;
    dotnet)
        check_prerequisite dotnet "dotnet-runtime-8.0" "--info" || prereq_ok=false
        ;;
    *)
        err "Unknown SERVICE_TYPE: ${SERVICE_TYPE}"
        exit 1
        ;;
esac

if [[ "$prereq_ok" != "true" ]]; then
    err "Missing prerequisites. Install them and re-run this script."
    exit 1
fi

# ── Create zylkerkart system user ────────────────────────────────────────────
if ! id -u zylkerkart &>/dev/null; then
    log "Creating system user 'zylkerkart'..."
    useradd --system --shell /usr/sbin/nologin --home-dir /opt/zylkerkart \
            --create-home zylkerkart
    info "User 'zylkerkart' created"
else
    info "User 'zylkerkart' already exists"
fi

# ── Stop existing service if running ─────────────────────────────────────────
if systemctl is-active --quiet "${UNIT_NAME}.service" 2>/dev/null; then
    warn "Stopping existing ${UNIT_NAME} service..."
    systemctl stop "${UNIT_NAME}.service"
    info "Service stopped"
fi

# ── Create directories ──────────────────────────────────────────────────────
log "Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$CHAOS_DIR"

# ── Copy application files ──────────────────────────────────────────────────
log "Copying application files to ${INSTALL_DIR}..."

# Clean old files (preserve venv for Python to speed up upgrades)
if [[ "$SERVICE_TYPE" == "python" ]]; then
    # Keep venv, remove everything else
    find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 ! -name 'venv' -exec rm -rf {} +
else
    rm -rf "${INSTALL_DIR:?}"/*
fi

# Copy bin/ contents to install dir
if [[ -d "$SCRIPT_DIR/bin" ]]; then
    cp -a "$SCRIPT_DIR/bin/." "$INSTALL_DIR/"
fi

# ── Python: Create/update virtual environment ───────────────────────────────
if [[ "$SERVICE_TYPE" == "python" ]]; then
    log "Setting up Python virtual environment..."
    if [[ ! -d "$INSTALL_DIR/venv" ]]; then
        python3 -m venv "$INSTALL_DIR/venv"
        info "Virtual environment created"
    else
        info "Virtual environment already exists (reusing)"
    fi

    if [[ -f "$INSTALL_DIR/requirements.txt" ]]; then
        log "Installing Python dependencies (requires internet)..."
        "$INSTALL_DIR/venv/bin/pip" install --upgrade pip -q
        "$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt" -q
        info "Dependencies installed"
    else
        warn "No requirements.txt found — skipping pip install"
    fi
fi

# ── Install systemd unit file ───────────────────────────────────────────────
log "Installing systemd unit..."
if [[ -d "$SCRIPT_DIR/systemd" ]]; then
    cp "$SCRIPT_DIR/systemd/${UNIT_NAME}.service" "$SYSTEMD_DIR/"
    info "Installed ${SYSTEMD_DIR}/${UNIT_NAME}.service"
fi

# ── Install env config template ─────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
    if [[ -d "$SCRIPT_DIR/config" ]]; then
        local_env=$(find "$SCRIPT_DIR/config" -name "*.env.example" -o -name "*.env" | head -1)
        if [[ -n "$local_env" ]]; then
            cp "$local_env" "$ENV_FILE"
            info "Installed env template to ${ENV_FILE}"
            warn ">>> EDIT ${ENV_FILE} with your actual server IPs and credentials <<<"
        fi
    fi
else
    info "Env file ${ENV_FILE} already exists — NOT overwriting (preserving your config)"
fi

# ── Set ownership and permissions ────────────────────────────────────────────
log "Setting permissions..."
chown -R zylkerkart:zylkerkart "$INSTALL_DIR"
chown -R zylkerkart:zylkerkart "$CHAOS_DIR"
chmod 600 "$ENV_FILE" 2>/dev/null || true

# Make Go binary executable
if [[ "$SERVICE_TYPE" == "go" ]]; then
    find "$INSTALL_DIR" -type f -executable -o -name "search-service" | head -1 | xargs -r chmod +x
    # Ensure the binary is executable
    [[ -f "$INSTALL_DIR/search-service" ]] && chmod +x "$INSTALL_DIR/search-service"
fi

# ── Reload systemd and enable service ───────────────────────────────────────
log "Enabling service..."
systemctl daemon-reload
systemctl enable "${UNIT_NAME}.service"
info "Service ${UNIT_NAME} enabled (will start on boot)"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "============================================================================="
echo -e "${GREEN} ZylkerKart ${SERVICE_NAME} installed successfully!${NC}"
echo "============================================================================="
echo ""
echo "  Install directory:  ${INSTALL_DIR}"
echo "  Systemd unit:       ${UNIT_NAME}.service"
echo "  Config file:        ${ENV_FILE}"
echo "  Service port:       ${SERVICE_PORT}"
echo "  Chaos config dir:   ${CHAOS_DIR}"
echo ""
echo "  Next steps:"
echo "  ────────────"
echo "  1. Edit the configuration file:"
echo "     sudo nano ${ENV_FILE}"
echo ""
echo "  2. Update server IPs and credentials for your environment"
echo ""
echo "  3. Start the service:"
echo "     sudo systemctl start ${UNIT_NAME}"
echo ""
echo "  4. Check status:"
echo "     sudo systemctl status ${UNIT_NAME}"
echo ""
echo "  5. View logs:"
echo "     sudo journalctl -u ${UNIT_NAME} -f"
echo ""
echo "============================================================================="
