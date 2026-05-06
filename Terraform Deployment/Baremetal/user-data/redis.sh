#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

VERSION="${version}"
RELEASE_URL="https://github.com/site24x7/demo-apps/releases/download/$${VERSION}"

echo "=== ZylkerKart Redis: Starting setup (version $${VERSION}) ==="

# Install Redis
apt-get install -y redis-server

# Download artifact from GitHub releases
cd /tmp
curl -fsSL "$${RELEASE_URL}/zylkerkart-redis-$${VERSION}.tar.gz" -o zylkerkart-redis.tar.gz
tar -xzf zylkerkart-redis.tar.gz
cd zylkerkart-redis-$${VERSION}

# Run the bundled setup script
sudo ./setup-redis.sh

# Enable and start Redis
systemctl enable redis-server
systemctl start redis-server

echo "=== ZylkerKart Redis: Setup complete ==="

# Install Site24x7 Full Stack Agent
echo "=== Installing Site24x7 Full Stack Agent ==="
wget https://staticdownloads.site24x7.com/server/Site24x7FullStackAgent_LinuxIns.sh
bash Site24x7FullStackAgent_LinuxIns.sh -i -key=${site24x7_key} -automation=true -apm_insight=true -ebpf=true
echo "=== Site24x7 Agent Installation Complete ==="
