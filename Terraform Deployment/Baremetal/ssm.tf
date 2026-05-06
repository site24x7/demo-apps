# ── SSM Documents ─────────────────────────────────────────────────────────────

# ── MySQL Setup ───────────────────────────────────────────────────────────────
resource "aws_ssm_document" "mysql_setup" {
  name            = "zylkerkart-mysql-setup"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Install MySQL 8.0, configure remote access, download artifact, and seed data"
    parameters = {
      Version = {
        type        = "String"
        description = "Artifact version"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "installAndSeedMySQL"
        inputs = {
          timeoutSeconds = "900"
          runCommand = [
            "#!/bin/bash",
            "set -euo pipefail",
            "export DEBIAN_FRONTEND=noninteractive",
            "",
            "VERSION=\"{{ Version }}\"",
            "RELEASE_URL=\"https://github.com/site24x7/demo-apps/releases/download/$${VERSION}\"",
            "",
            "echo '=== ZylkerKart MySQL: Starting setup ==='",
            "",
            "# Update package lists and install MySQL 8.0",
            "apt-get update -y",
            "apt-get install -y mysql-server-8.0 curl wget ca-certificates gnupg",
            "",
            "# Configure MySQL to allow remote connections",
            "sed -i 's/^bind-address\\s*=.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf",
            "",
            "# Enable and start MySQL",
            "systemctl enable mysql",
            "systemctl start mysql",
            "",
            "# Set root password and enable remote access (idempotent)",
            "if mysql -u root -e 'SELECT 1' &>/dev/null; then",
            "MYSQL_CMD='mysql -u root'",
            "else",
            "MYSQL_CMD=\"mysql -u root -p'ZylkerKart@2024'\"",
            "fi",
            "",
            "eval $MYSQL_CMD <<'MYSQL_EOF'",
            "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'ZylkerKart@2024';",
            "CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH mysql_native_password BY 'ZylkerKart@2024';",
            "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;",
            "FLUSH PRIVILEGES;",
            "MYSQL_EOF",
            "",
            "systemctl restart mysql",
            "",
            "# Tune MySQL for faster seed import",
            "mysql -u root -p'ZylkerKart@2024' -e \"SET GLOBAL innodb_flush_log_at_trx_commit = 0; SET GLOBAL max_allowed_packet = 67108864; SET GLOBAL innodb_change_buffering = 'all';\"",
            "",
            "# Download artifact",
            "cd /tmp",
            "curl -fsSL \"$${RELEASE_URL}/zylkerkart-mysql-$${VERSION}.tar.gz\" -o zylkerkart-mysql.tar.gz",
            "tar -xzf zylkerkart-mysql.tar.gz",
            "cd zylkerkart-mysql-$${VERSION}",
            "",
            "# Configure and run setup",
            "cat > mysql.env <<'ENV'",
            "MYSQL_ROOT_PASSWORD=ZylkerKart@2024",
            "ENV",
            "",
            "sudo ./setup-mysql.sh",
            "",
            "echo '=== ZylkerKart MySQL: Setup complete ==='"
          ]
        }
      }
    ]
  })

  tags = {
    Name    = "zylkerkart-mysql-setup"
    Project = "ZylkerKart"
  }
}

# ── Redis Setup ───────────────────────────────────────────────────────────────
resource "aws_ssm_document" "redis_setup" {
  name            = "zylkerkart-redis-setup"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Install and configure Redis"
    parameters = {
      Version = {
        type        = "String"
        description = "Artifact version"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "installRedis"
        inputs = {
          timeoutSeconds = "600"
          runCommand = [
            "#!/bin/bash",
            "set -euo pipefail",
            "export DEBIAN_FRONTEND=noninteractive",
            "",
            "VERSION=\"{{ Version }}\"",
            "RELEASE_URL=\"https://github.com/site24x7/demo-apps/releases/download/$${VERSION}\"",
            "",
            "echo '=== ZylkerKart Redis: Starting setup ==='",
            "",
            "# Install Redis",
            "apt-get update -y",
            "apt-get install -y redis-server curl",
            "",
            "# Download artifact",
            "cd /tmp",
            "curl -fsSL \"$${RELEASE_URL}/zylkerkart-redis-$${VERSION}.tar.gz\" -o zylkerkart-redis.tar.gz",
            "tar -xzf zylkerkart-redis.tar.gz",
            "cd zylkerkart-redis-$${VERSION}",
            "",
            "# Run setup",
            "sudo ./setup-redis.sh",
            "",
            "# Enable and start Redis",
            "systemctl enable redis-server",
            "systemctl start redis-server",
            "",
            "echo '=== ZylkerKart Redis: Setup complete ==='"
          ]
        }
      }
    ]
  })

  tags = {
    Name    = "zylkerkart-redis-setup"
    Project = "ZylkerKart"
  }
}

# ── Product Service Setup ─────────────────────────────────────────────────────
resource "aws_ssm_document" "product_setup" {
  name            = "zylkerkart-product-setup"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Install Java 17 and deploy Product Service"
    parameters = {
      Version = {
        type        = "String"
        description = "Artifact version"
      }
      MysqlHost = {
        type        = "String"
        description = "MySQL private IP"
      }
      RedisHost = {
        type        = "String"
        description = "Redis private IP"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "deployProductService"
        inputs = {
          timeoutSeconds = "600"
          runCommand = [
            "#!/bin/bash",
            "set -euo pipefail",
            "export DEBIAN_FRONTEND=noninteractive",
            "",
            "VERSION=\"{{ Version }}\"",
            "MYSQL_HOST=\"{{ MysqlHost }}\"",
            "REDIS_HOST=\"{{ RedisHost }}\"",
            "RELEASE_URL=\"https://github.com/site24x7/demo-apps/releases/download/$${VERSION}\"",
            "",
            "echo '=== ZylkerKart Product Service: Starting setup ==='",
            "",
            "# Install Java 17",
            "apt-get update -y",
            "apt-get install -y openjdk-17-jre-headless curl wget",
            "",
            "# Download artifact",
            "cd /tmp",
            "curl -fsSL \"$${RELEASE_URL}/zylkerkart-product-service-$${VERSION}-linux-amd64.tar.gz\" -o zylkerkart-product-service.tar.gz",
            "tar -xzf zylkerkart-product-service.tar.gz",
            "cd zylkerkart-product-service-$${VERSION}-linux-amd64",
            "",
            "# Install",
            "sudo ./install.sh",
            "",
            "# Configure",
            "ENV_FILE=\"/etc/zylkerkart/product-service.env\"",
            "sed -i \"s|MYSQL_HOST|$${MYSQL_HOST}|g\" \"$${ENV_FILE}\"",
            "sed -i \"s|=REDIS_HOST|=$${REDIS_HOST}|g\" \"$${ENV_FILE}\"",
            "",
            "# Enable Chaos SDK",
            "cat >> \"$${ENV_FILE}\" <<'CHAOS'",
            "CHAOS_SDK_ENABLED=true",
            "CHAOS_SDK_APP_NAME=product-service",
            "CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults",
            "CHAOS",
            "",
            "# Start service",
            "systemctl start zylkerkart-product-service",
            "",
            "echo '=== ZylkerKart Product Service: Setup complete ==='"
          ]
        }
      }
    ]
  })

  tags = {
    Name    = "zylkerkart-product-setup"
    Project = "ZylkerKart"
  }
}

# ── Order Service Setup ───────────────────────────────────────────────────────
resource "aws_ssm_document" "order_setup" {
  name            = "zylkerkart-order-setup"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Install Node.js 18 and deploy Order Service"
    parameters = {
      Version = {
        type        = "String"
        description = "Artifact version"
      }
      MysqlHost = {
        type        = "String"
        description = "MySQL private IP"
      }
      RedisHost = {
        type        = "String"
        description = "Redis private IP"
      }
      PaymentHost = {
        type        = "String"
        description = "Payment Service private IP"
      }
      AuthHost = {
        type        = "String"
        description = "Auth Service private IP"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "deployOrderService"
        inputs = {
          timeoutSeconds = "600"
          runCommand = [
            "#!/bin/bash",
            "set -euo pipefail",
            "export DEBIAN_FRONTEND=noninteractive",
            "",
            "VERSION=\"{{ Version }}\"",
            "MYSQL_HOST=\"{{ MysqlHost }}\"",
            "REDIS_HOST=\"{{ RedisHost }}\"",
            "PAYMENT_HOST=\"{{ PaymentHost }}\"",
            "AUTH_HOST=\"{{ AuthHost }}\"",
            "RELEASE_URL=\"https://github.com/site24x7/demo-apps/releases/download/$${VERSION}\"",
            "",
            "echo '=== ZylkerKart Order Service: Starting setup ==='",
            "",
            "# Install Node.js 18",
            "apt-get update -y",
            "apt-get install -y curl ca-certificates gnupg",
            "curl -fsSL https://deb.nodesource.com/setup_18.x | bash -",
            "apt-get install -y nodejs",
            "",
            "# Download artifact",
            "cd /tmp",
            "curl -fsSL \"$${RELEASE_URL}/zylkerkart-order-service-$${VERSION}-linux-amd64.tar.gz\" -o zylkerkart-order-service.tar.gz",
            "tar -xzf zylkerkart-order-service.tar.gz",
            "cd zylkerkart-order-service-$${VERSION}-linux-amd64",
            "",
            "# Install",
            "sudo ./install.sh",
            "",
            "# Configure",
            "ENV_FILE=\"/etc/zylkerkart/order-service.env\"",
            "sed -i \"s|MYSQL_HOST|$${MYSQL_HOST}|g\" \"$${ENV_FILE}\"",
            "sed -i \"s|=REDIS_HOST|=$${REDIS_HOST}|g\" \"$${ENV_FILE}\"",
            "sed -i \"s|PAYMENT_HOST|$${PAYMENT_HOST}|g\" \"$${ENV_FILE}\"",
            "sed -i \"s|AUTH_HOST|$${AUTH_HOST}|g\" \"$${ENV_FILE}\"",
            "",
            "# Enable Chaos SDK",
            "cat >> \"$${ENV_FILE}\" <<'CHAOS'",
            "CHAOS_SDK_ENABLED=true",
            "CHAOS_SDK_APP_NAME=order-service",
            "CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults",
            "CHAOS",
            "",
            "# Start service",
            "systemctl start zylkerkart-order-service",
            "",
            "echo '=== ZylkerKart Order Service: Setup complete ==='"
          ]
        }
      }
    ]
  })

  tags = {
    Name    = "zylkerkart-order-setup"
    Project = "ZylkerKart"
  }
}

# ── Search Service Setup ──────────────────────────────────────────────────────
resource "aws_ssm_document" "search_setup" {
  name            = "zylkerkart-search-setup"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Deploy Search Service (Go static binary)"
    parameters = {
      Version = {
        type        = "String"
        description = "Artifact version"
      }
      MysqlHost = {
        type        = "String"
        description = "MySQL private IP"
      }
      RedisHost = {
        type        = "String"
        description = "Redis private IP"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "deploySearchService"
        inputs = {
          timeoutSeconds = "600"
          runCommand = [
            "#!/bin/bash",
            "set -euo pipefail",
            "export DEBIAN_FRONTEND=noninteractive",
            "",
            "VERSION=\"{{ Version }}\"",
            "MYSQL_HOST=\"{{ MysqlHost }}\"",
            "REDIS_HOST=\"{{ RedisHost }}\"",
            "RELEASE_URL=\"https://github.com/site24x7/demo-apps/releases/download/$${VERSION}\"",
            "",
            "echo '=== ZylkerKart Search Service: Starting setup ==='",
            "",
            "apt-get update -y",
            "apt-get install -y curl ca-certificates",
            "",
            "# Download artifact",
            "cd /tmp",
            "curl -fsSL \"$${RELEASE_URL}/zylkerkart-search-service-$${VERSION}-linux-amd64.tar.gz\" -o zylkerkart-search-service.tar.gz",
            "tar -xzf zylkerkart-search-service.tar.gz",
            "cd zylkerkart-search-service-$${VERSION}-linux-amd64",
            "",
            "# Install",
            "sudo ./install.sh",
            "",
            "# Configure",
            "ENV_FILE=\"/etc/zylkerkart/search-service.env\"",
            "sed -i \"s|MYSQL_HOST|$${MYSQL_HOST}|g\" \"$${ENV_FILE}\"",
            "sed -i \"s|=REDIS_HOST|=$${REDIS_HOST}|g\" \"$${ENV_FILE}\"",
            "",
            "# Enable Chaos SDK",
            "cat >> \"$${ENV_FILE}\" <<'CHAOS'",
            "CHAOS_SDK_ENABLED=true",
            "CHAOS_SDK_APP_NAME=search-service",
            "CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults",
            "CHAOS",
            "",
            "# Start service",
            "systemctl start zylkerkart-search-service",
            "",
            "echo '=== ZylkerKart Search Service: Setup complete ==='"
          ]
        }
      }
    ]
  })

  tags = {
    Name    = "zylkerkart-search-setup"
    Project = "ZylkerKart"
  }
}

# ── Payment Service Setup ─────────────────────────────────────────────────────
resource "aws_ssm_document" "payment_setup" {
  name            = "zylkerkart-payment-setup"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Install Python 3.11 and deploy Payment Service"
    parameters = {
      Version = {
        type        = "String"
        description = "Artifact version"
      }
      MysqlHost = {
        type        = "String"
        description = "MySQL private IP"
      }
      RedisHost = {
        type        = "String"
        description = "Redis private IP"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "deployPaymentService"
        inputs = {
          timeoutSeconds = "600"
          runCommand = [
            "#!/bin/bash",
            "set -euo pipefail",
            "export DEBIAN_FRONTEND=noninteractive",
            "",
            "VERSION=\"{{ Version }}\"",
            "MYSQL_HOST=\"{{ MysqlHost }}\"",
            "REDIS_HOST=\"{{ RedisHost }}\"",
            "RELEASE_URL=\"https://github.com/site24x7/demo-apps/releases/download/$${VERSION}\"",
            "",
            "echo '=== ZylkerKart Payment Service: Starting setup ==='",
            "",
            "# Install Python 3.11",
            "apt-get update -y",
            "apt-get install -y curl ca-certificates python3.11 python3.11-venv python3.11-dev python3-pip",
            "",
            "# Pre-create venv for payment-service (do NOT change system python3)",
            "mkdir -p /opt/zylkerkart/payment-service",
            "python3.11 -m venv /opt/zylkerkart/payment-service/venv",
            "",
            "# Download artifact",
            "cd /tmp",
            "curl -fsSL \"$${RELEASE_URL}/zylkerkart-payment-service-$${VERSION}-linux-amd64.tar.gz\" -o zylkerkart-payment-service.tar.gz",
            "tar -xzf zylkerkart-payment-service.tar.gz",
            "cd zylkerkart-payment-service-$${VERSION}-linux-amd64",
            "",
            "# Install",
            "sudo ./install.sh",
            "",
            "# Configure",
            "ENV_FILE=\"/etc/zylkerkart/payment-service.env\"",
            "sed -i \"s|MYSQL_HOST|$${MYSQL_HOST}|g\" \"$${ENV_FILE}\"",
            "sed -i \"s|=REDIS_HOST|=$${REDIS_HOST}|g\" \"$${ENV_FILE}\"",
            "",
            "# Enable Chaos SDK",
            "cat >> \"$${ENV_FILE}\" <<'CHAOS'",
            "CHAOS_SDK_ENABLED=true",
            "CHAOS_SDK_APP_NAME=payment-service",
            "CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults",
            "CHAOS",
            "",
            "# Start service",
            "systemctl start zylkerkart-payment-service",
            "",
            "echo '=== ZylkerKart Payment Service: Setup complete ==='"
          ]
        }
      }
    ]
  })

  tags = {
    Name    = "zylkerkart-payment-setup"
    Project = "ZylkerKart"
  }
}

# ── Auth Service Setup ────────────────────────────────────────────────────────
resource "aws_ssm_document" "auth_setup" {
  name            = "zylkerkart-auth-setup"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Install .NET 8 and deploy Auth Service"
    parameters = {
      Version = {
        type        = "String"
        description = "Artifact version"
      }
      MysqlHost = {
        type        = "String"
        description = "MySQL private IP"
      }
      RedisHost = {
        type        = "String"
        description = "Redis private IP"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "deployAuthService"
        inputs = {
          timeoutSeconds = "600"
          runCommand = [
            "#!/bin/bash",
            "set -euo pipefail",
            "export DEBIAN_FRONTEND=noninteractive",
            "",
            "VERSION=\"{{ Version }}\"",
            "MYSQL_HOST=\"{{ MysqlHost }}\"",
            "REDIS_HOST=\"{{ RedisHost }}\"",
            "RELEASE_URL=\"https://github.com/site24x7/demo-apps/releases/download/$${VERSION}\"",
            "",
            "echo '=== ZylkerKart Auth Service: Starting setup ==='",
            "",
            "# Install .NET 8 ASP.NET Core runtime",
            "apt-get update -y",
            "apt-get install -y curl wget ca-certificates gnupg apt-transport-https",
            "wget -qO /tmp/packages-microsoft-prod.deb https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb",
            "dpkg -i /tmp/packages-microsoft-prod.deb",
            "apt-get update -y",
            "apt-get install -y aspnetcore-runtime-8.0",
            "",
            "# Download artifact",
            "cd /tmp",
            "curl -fsSL \"$${RELEASE_URL}/zylkerkart-auth-service-$${VERSION}-linux-amd64.tar.gz\" -o zylkerkart-auth-service.tar.gz",
            "tar -xzf zylkerkart-auth-service.tar.gz",
            "cd zylkerkart-auth-service-$${VERSION}-linux-amd64",
            "",
            "# Install",
            "sudo ./install.sh",
            "",
            "# Configure",
            "ENV_FILE=\"/etc/zylkerkart/auth-service.env\"",
            "sed -i \"s|MYSQL_HOST|$${MYSQL_HOST}|g\" \"$${ENV_FILE}\"",
            "sed -i \"s|=REDIS_HOST|=$${REDIS_HOST}|g\" \"$${ENV_FILE}\"",
            "",
            "# Enable Chaos SDK",
            "cat >> \"$${ENV_FILE}\" <<'CHAOS'",
            "CHAOS_SDK_ENABLED=true",
            "CHAOS_SDK_APP_NAME=auth-service",
            "CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults",
            "CHAOS",
            "",
            "# Start service",
            "systemctl start zylkerkart-auth-service",
            "",
            "echo '=== ZylkerKart Auth Service: Setup complete ==='"
          ]
        }
      }
    ]
  })

  tags = {
    Name    = "zylkerkart-auth-setup"
    Project = "ZylkerKart"
  }
}

# ── Storefront Setup ──────────────────────────────────────────────────────────
resource "aws_ssm_document" "storefront_setup" {
  name            = "zylkerkart-storefront-setup"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Install Java 17 and deploy Storefront"
    parameters = {
      Version = {
        type        = "String"
        description = "Artifact version"
      }
      ProductHost = {
        type        = "String"
        description = "Product Service private IP"
      }
      OrderHost = {
        type        = "String"
        description = "Order Service private IP"
      }
      SearchHost = {
        type        = "String"
        description = "Search Service private IP"
      }
      PaymentHost = {
        type        = "String"
        description = "Payment Service private IP"
      }
      AuthHost = {
        type        = "String"
        description = "Auth Service private IP"
      }
      RedisHost = {
        type        = "String"
        description = "Redis private IP"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "deployStorefront"
        inputs = {
          timeoutSeconds = "600"
          runCommand = [
            "#!/bin/bash",
            "set -euo pipefail",
            "export DEBIAN_FRONTEND=noninteractive",
            "",
            "VERSION=\"{{ Version }}\"",
            "PRODUCT_HOST=\"{{ ProductHost }}\"",
            "ORDER_HOST=\"{{ OrderHost }}\"",
            "SEARCH_HOST=\"{{ SearchHost }}\"",
            "PAYMENT_HOST=\"{{ PaymentHost }}\"",
            "AUTH_HOST=\"{{ AuthHost }}\"",
            "REDIS_HOST=\"{{ RedisHost }}\"",
            "RELEASE_URL=\"https://github.com/site24x7/demo-apps/releases/download/$${VERSION}\"",
            "",
            "echo '=== ZylkerKart Storefront: Starting setup ==='",
            "",
            "# Install Java 17",
            "apt-get update -y",
            "apt-get install -y openjdk-17-jre-headless curl wget",
            "",
            "# Download artifact",
            "cd /tmp",
            "curl -fsSL \"$${RELEASE_URL}/zylkerkart-storefront-$${VERSION}-linux-amd64.tar.gz\" -o zylkerkart-storefront.tar.gz",
            "tar -xzf zylkerkart-storefront.tar.gz",
            "cd zylkerkart-storefront-$${VERSION}-linux-amd64",
            "",
            "# Install",
            "sudo ./install.sh",
            "",
            "# Configure",
            "ENV_FILE=\"/etc/zylkerkart/storefront.env\"",
            "sed -i \"s|PRODUCT_SERVER_IP|$${PRODUCT_HOST}|g\" \"$${ENV_FILE}\"",
            "sed -i \"s|ORDER_SERVER_IP|$${ORDER_HOST}|g\" \"$${ENV_FILE}\"",
            "sed -i \"s|SEARCH_SERVER_IP|$${SEARCH_HOST}|g\" \"$${ENV_FILE}\"",
            "sed -i \"s|PAYMENT_SERVER_IP|$${PAYMENT_HOST}|g\" \"$${ENV_FILE}\"",
            "sed -i \"s|AUTH_SERVER_IP|$${AUTH_HOST}|g\" \"$${ENV_FILE}\"",
            "sed -i \"s|=REDIS_SERVER_IP|=$${REDIS_HOST}|g\" \"$${ENV_FILE}\"",
            "",
            "# Set server port (app defaults to 80 which requires root)",
            "sed -i 's|^# SERVER_PORT=.*|SERVER_PORT=8080|' \"$${ENV_FILE}\"",
            "",
            "# Enable Chaos SDK",
            "cat >> \"$${ENV_FILE}\" <<'CHAOS'",
            "CHAOS_SDK_ENABLED=true",
            "CHAOS_SDK_APP_NAME=storefront",
            "CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults",
            "CHAOS",
            "",
            "# Start service",
            "systemctl start zylkerkart-storefront",
            "",
            "echo '=== ZylkerKart Storefront: Setup complete ==='"
          ]
        }
      }
    ]
  })

  tags = {
    Name    = "zylkerkart-storefront-setup"
    Project = "ZylkerKart"
  }
}

# ── SSM Associations (auto-trigger on instance) ──────────────────────────────

resource "aws_ssm_association" "mysql_setup" {
  name = aws_ssm_document.mysql_setup.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.mysql.id]
  }

  parameters = {
    Version = var.artifact_version
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.ssm_logs.id
    s3_key_prefix  = "mysql/"
    s3_region      = var.aws_region
  }

  tags = {
    Name    = "zylkerkart-mysql-association"
    Project = "ZylkerKart"
  }
}

resource "aws_ssm_association" "redis_setup" {
  name = aws_ssm_document.redis_setup.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.redis.id]
  }

  parameters = {
    Version = var.artifact_version
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.ssm_logs.id
    s3_key_prefix  = "redis/"
    s3_region      = var.aws_region
  }

  tags = {
    Name    = "zylkerkart-redis-association"
    Project = "ZylkerKart"
  }
}

resource "aws_ssm_association" "product_setup" {
  name = aws_ssm_document.product_setup.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.product_service.id]
  }

  parameters = {
    Version   = var.artifact_version
    MysqlHost = aws_instance.mysql.private_ip
    RedisHost = aws_instance.redis.private_ip
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.ssm_logs.id
    s3_key_prefix  = "product/"
    s3_region      = var.aws_region
  }

  tags = {
    Name    = "zylkerkart-product-association"
    Project = "ZylkerKart"
  }
}

resource "aws_ssm_association" "order_setup" {
  name = aws_ssm_document.order_setup.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.order_service.id]
  }

  parameters = {
    Version     = var.artifact_version
    MysqlHost   = aws_instance.mysql.private_ip
    RedisHost   = aws_instance.redis.private_ip
    PaymentHost = aws_instance.payment_service.private_ip
    AuthHost    = aws_instance.auth_service.private_ip
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.ssm_logs.id
    s3_key_prefix  = "order/"
    s3_region      = var.aws_region
  }

  tags = {
    Name    = "zylkerkart-order-association"
    Project = "ZylkerKart"
  }
}

resource "aws_ssm_association" "search_setup" {
  name = aws_ssm_document.search_setup.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.search_service.id]
  }

  parameters = {
    Version   = var.artifact_version
    MysqlHost = aws_instance.mysql.private_ip
    RedisHost = aws_instance.redis.private_ip
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.ssm_logs.id
    s3_key_prefix  = "search/"
    s3_region      = var.aws_region
  }

  tags = {
    Name    = "zylkerkart-search-association"
    Project = "ZylkerKart"
  }
}

resource "aws_ssm_association" "payment_setup" {
  name = aws_ssm_document.payment_setup.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.payment_service.id]
  }

  parameters = {
    Version   = var.artifact_version
    MysqlHost = aws_instance.mysql.private_ip
    RedisHost = aws_instance.redis.private_ip
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.ssm_logs.id
    s3_key_prefix  = "payment/"
    s3_region      = var.aws_region
  }

  tags = {
    Name    = "zylkerkart-payment-association"
    Project = "ZylkerKart"
  }
}

resource "aws_ssm_association" "auth_setup" {
  name = aws_ssm_document.auth_setup.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.auth_service.id]
  }

  parameters = {
    Version   = var.artifact_version
    MysqlHost = aws_instance.mysql.private_ip
    RedisHost = aws_instance.redis.private_ip
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.ssm_logs.id
    s3_key_prefix  = "auth/"
    s3_region      = var.aws_region
  }

  tags = {
    Name    = "zylkerkart-auth-association"
    Project = "ZylkerKart"
  }
}

resource "aws_ssm_association" "storefront_setup" {
  name = aws_ssm_document.storefront_setup.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.storefront.id]
  }

  parameters = {
    Version     = var.artifact_version
    ProductHost = aws_instance.product_service.private_ip
    OrderHost   = aws_instance.order_service.private_ip
    SearchHost  = aws_instance.search_service.private_ip
    PaymentHost = aws_instance.payment_service.private_ip
    AuthHost    = aws_instance.auth_service.private_ip
    RedisHost   = aws_instance.redis.private_ip
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.ssm_logs.id
    s3_key_prefix  = "storefront/"
    s3_region      = var.aws_region
  }

  tags = {
    Name    = "zylkerkart-storefront-association"
    Project = "ZylkerKart"
  }
}
