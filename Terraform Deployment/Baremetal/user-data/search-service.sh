#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

VERSION="${version}"
RELEASE_URL="https://github.com/site24x7/demo-apps/releases/download/$${VERSION}"

echo "=== ZylkerKart Search Service: Starting setup (version $${VERSION}) ==="

# Install prerequisites
apt-get install -y curl ca-certificates

# Download artifact from GitHub releases (Go static binary — no runtime needed)
cd /tmp
curl -fsSL "$${RELEASE_URL}/zylkerkart-search-service-$${VERSION}-linux-amd64.tar.gz" \
  -o zylkerkart-search-service.tar.gz
tar -xzf zylkerkart-search-service.tar.gz
cd zylkerkart-search-service-$${VERSION}-linux-amd64

# Run the bundled install script (sets up user, directories, systemd unit)
sudo ./install.sh

# Configure the environment file with real service IPs
ENV_FILE="/opt/zylkerkart/config/search-service.env"
sed -i "s|MYSQL_HOST|${mysql_host}|g" "$${ENV_FILE}"
sed -i "s|=REDIS_HOST|=${redis_host}|g" "$${ENV_FILE}"

# Enable Chaos SDK
cat >> "$${ENV_FILE}" <<'CHAOS'
CHAOS_SDK_ENABLED=true
CHAOS_SDK_APP_NAME=search-service
CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults
CHAOS

# Start the service
systemctl start search-service

echo "=== ZylkerKart Search Service: Setup complete ==="

# Install Site24x7 Full Stack Agent
echo "=== Installing Site24x7 Full Stack Agent ==="
wget https://staticdownloads.site24x7.com/server/Site24x7FullStackAgent_LinuxIns.sh
bash Site24x7FullStackAgent_LinuxIns.sh -i -key=${site24x7_key} -automation=true -apm_insight=true -ebpf=true
echo "=== Site24x7 Agent Installation Complete ==="
