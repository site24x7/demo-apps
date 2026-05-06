#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

VERSION="${version}"
RELEASE_URL="https://github.com/site24x7/demo-apps/releases/download/$${VERSION}"

echo "=== ZylkerKart Auth Service: Starting setup (version $${VERSION}) ==="

# Install prerequisites
apt-get install -y curl wget ca-certificates gnupg software-properties-common apt-transport-https

# Install .NET 8 ASP.NET Core runtime
wget -qO /tmp/packages-microsoft-prod.deb \
  https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb
dpkg -i /tmp/packages-microsoft-prod.deb
apt-get install -y aspnetcore-runtime-8.0

# Download artifact from GitHub releases
cd /tmp
curl -fsSL "$${RELEASE_URL}/zylkerkart-auth-service-$${VERSION}-linux-amd64.tar.gz" \
  -o zylkerkart-auth-service.tar.gz
tar -xzf zylkerkart-auth-service.tar.gz
cd zylkerkart-auth-service-$${VERSION}-linux-amd64

# Run the bundled install script (sets up user, directories, systemd unit)
sudo ./install.sh

# Configure the environment file with real service IPs
ENV_FILE="/opt/zylkerkart/config/auth-service.env"
sed -i "s|MYSQL_HOST|${mysql_host}|g" "$${ENV_FILE}"
sed -i "s|=REDIS_HOST|=${redis_host}|g" "$${ENV_FILE}"

# Enable Chaos SDK
cat >> "$${ENV_FILE}" <<'CHAOS'
CHAOS_SDK_ENABLED=true
CHAOS_SDK_APP_NAME=auth-service
CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults
CHAOS

# Start the service
systemctl start auth-service

echo "=== ZylkerKart Auth Service: Setup complete ==="

# Install Site24x7 Full Stack Agent
echo "=== Installing Site24x7 Full Stack Agent ==="
wget https://staticdownloads.site24x7.com/server/Site24x7FullStackAgent_LinuxIns.sh
bash Site24x7FullStackAgent_LinuxIns.sh -i -key=${site24x7_key} -automation=true -apm_insight=true -ebpf=true
echo "=== Site24x7 Agent Installation Complete ==="
