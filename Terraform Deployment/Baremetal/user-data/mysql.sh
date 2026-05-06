#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

VERSION="${version}"
RELEASE_URL="https://github.com/site24x7/demo-apps/releases/download/$${VERSION}"

echo "=== ZylkerKart MySQL: Starting setup (version $${VERSION}) ==="

# Install MySQL 8.0
apt-get install -y mysql-server-8.0 curl wget ca-certificates gnupg

# Configure MySQL to allow remote connections
sed -i 's/^bind-address\s*=.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf

# Enable and start MySQL
systemctl enable mysql
systemctl start mysql

# Set root password and enable remote access (Ubuntu 22.04 uses auth_socket by default)
mysql -u root <<'MYSQL_EOF'
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'ZylkerKart@2024';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH mysql_native_password BY 'ZylkerKart@2024';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_EOF

systemctl restart mysql

# Tune MySQL for faster seed import on small instances
mysql -u root -p'ZylkerKart@2024' -e "
SET GLOBAL innodb_flush_log_at_trx_commit = 0;
SET GLOBAL max_allowed_packet = 67108864;
SET GLOBAL innodb_change_buffering = 'all';
"

# Download artifact from GitHub releases
cd /tmp
curl -fsSL "$${RELEASE_URL}/zylkerkart-mysql-$${VERSION}.tar.gz" -o zylkerkart-mysql.tar.gz
tar -xzf zylkerkart-mysql.tar.gz
cd zylkerkart-mysql-$${VERSION}

# Configure mysql.env with the root password
cat > mysql.env <<'ENV'
MYSQL_ROOT_PASSWORD=ZylkerKart@2024
ENV

# Run the bundled setup script
sudo ./setup-mysql.sh

echo "=== ZylkerKart MySQL: Setup complete ==="

# Install Site24x7 Full Stack Agent
echo "=== Installing Site24x7 Full Stack Agent ==="
wget https://staticdownloads.site24x7.com/server/Site24x7FullStackAgent_LinuxIns.sh
bash Site24x7FullStackAgent_LinuxIns.sh -i -key=${site24x7_key} -automation=true -apm_insight=true -ebpf=true
echo "=== Site24x7 Agent Installation Complete ==="
