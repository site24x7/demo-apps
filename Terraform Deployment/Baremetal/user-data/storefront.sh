#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

VERSION="${version}"
RELEASE_URL="https://github.com/site24x7/demo-apps/releases/download/$${VERSION}"

echo "=== ZylkerKart Storefront: Starting setup (version $${VERSION}) ==="

# Install prerequisites and OpenJDK 17
apt-get install -y curl wget ca-certificates gnupg software-properties-common openjdk-17-jre-headless

# Download artifact from GitHub releases
cd /tmp
curl -fsSL "$${RELEASE_URL}/zylkerkart-storefront-$${VERSION}-linux-amd64.tar.gz" \
  -o zylkerkart-storefront.tar.gz
tar -xzf zylkerkart-storefront.tar.gz
cd zylkerkart-storefront-$${VERSION}-linux-amd64

# Run the bundled install script (sets up user, directories, systemd unit)
sudo ./install.sh

# Configure the environment file with real service IPs
ENV_FILE="/etc/zylkerkart/storefront.env"
sed -i "s|PRODUCT_HOST|${product_host}|g" "$${ENV_FILE}"
sed -i "s|ORDER_HOST|${order_host}|g"     "$${ENV_FILE}"
sed -i "s|SEARCH_HOST|${search_host}|g"   "$${ENV_FILE}"
sed -i "s|PAYMENT_HOST|${payment_host}|g" "$${ENV_FILE}"
sed -i "s|AUTH_HOST|${auth_host}|g"       "$${ENV_FILE}"
sed -i "s|=REDIS_HOST|=${redis_host}|g"     "$${ENV_FILE}"

# Enable Chaos SDK
cat >> "$${ENV_FILE}" <<'CHAOS'
CHAOS_SDK_ENABLED=true
CHAOS_SDK_APP_NAME=storefront
CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults
CHAOS

# Start the service
systemctl start zylkerkart-storefront

echo "=== ZylkerKart Storefront: Setup complete ==="

# Install Site24x7 Full Stack Agent
echo "=== Installing Site24x7 Full Stack Agent ==="
wget https://staticdownloads.site24x7.com/server/Site24x7FullStackAgent_LinuxIns.sh
bash Site24x7FullStackAgent_LinuxIns.sh -i -key=${site24x7_key} -automation=true -apm_insight=true -ebpf=true
echo "=== Site24x7 Agent Installation Complete ==="
