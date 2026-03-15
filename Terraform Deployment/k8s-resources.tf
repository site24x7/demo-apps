# ─────────────────────────────────────────────────────────────────────────────
# ZylkerKart — Kubernetes Resources (mirrors scripts/deploy-k8s.sh)
# ─────────────────────────────────────────────────────────────────────────────

locals {
  cluster_dependency = var.cloud_provider == "azure" ? (
    length(azurerm_kubernetes_cluster.aks) > 0 ? azurerm_kubernetes_cluster.aks[0].id : ""
    ) : (
    length(aws_eks_node_group.default) > 0 ? aws_eks_node_group.default[0].id : ""
  )
}

# ════════════════════════════════════════════════════════════════════════════
# Step 2: Namespace
# ════════════════════════════════════════════════════════════════════════════
resource "kubernetes_namespace" "zylkerkart" {
  metadata {
    name = "zylkerkart"
    labels = {
      "app.kubernetes.io/part-of" = "zylkerkart"
    }
  }

  depends_on = [local.cluster_dependency]
}

resource "kubernetes_namespace" "monitoring" {
  count = local.enable_apm ? 1 : 0
  metadata {
    name = "monitoring"
    labels = {
      purpose = "apm-monitoring"
    }
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks,
    aws_eks_node_group.default,
  ]
}

# ════════════════════════════════════════════════════════════════════════════
# Step 3: ConfigMap
# ════════════════════════════════════════════════════════════════════════════
resource "kubernetes_config_map" "zylkerkart_config" {
  metadata {
    name      = "zylkerkart-config"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
  }

  data = {
    MYSQL_ROOT_PASSWORD     = var.mysql_root_password
    DB_HOST                 = "mysql"
    DB_PORT                 = "3306"
    DB_USER                 = "root"
    REDIS_HOST              = "redis"
    REDIS_PORT              = "6379"
    JWT_SECRET              = var.jwt_secret
    JWT_EXPIRY_MINUTES      = "15"
    JWT_REFRESH_EXPIRY_DAYS = "7"
    PRODUCT_SERVICE_URL     = "http://product-service:8081"
    ORDER_SERVICE_URL       = "http://order-service:8082"
    SEARCH_SERVICE_URL      = "http://search-service:8083"
    PAYMENT_SERVICE_URL     = "http://payment-service:8084"
    AUTH_SERVICE_URL        = "http://auth-service:8085"
    STOREFRONT_URL          = "http://storefront:80"
    S247_LICENSE_KEY        = local.enable_apm ? var.site24x7_license_key : "<your-site24x7-license-key>"
  }
}

# ════════════════════════════════════════════════════════════════════════════
# Step 4: MySQL — Deployment + PVC + Service
# ════════════════════════════════════════════════════════════════════════════
resource "kubernetes_persistent_volume_claim" "mysql_pvc" {
  metadata {
    name      = "mysql-pvc"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = local.storage_class
    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }

  wait_until_bound = false
}

resource "kubernetes_deployment" "mysql" {
  metadata {
    name      = "mysql"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
    labels    = { app = "mysql" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "mysql" }
    }
    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = { app = "mysql" }
      }
      spec {
        enable_service_links = false

        container {
          name              = "mysql"
          image_pull_policy = "Always"
          image             = "${var.docker_registry}/db:latest"

          port {
            container_port = 3306
          }

          env {
            name = "MYSQL_ROOT_PASSWORD"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "MYSQL_ROOT_PASSWORD"
              }
            }
          }

          volume_mount {
            name       = "mysql-data"
            mount_path = "/var/lib/mysql"
          }

          readiness_probe {
            exec {
              command = ["mysqladmin", "ping", "-h", "localhost", "-uroot", "-p${var.mysql_root_password}"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
          }

          liveness_probe {
            exec {
              command = ["mysqladmin", "ping", "-h", "localhost", "-uroot", "-p${var.mysql_root_password}"]
            }
            initial_delay_seconds = 60
            period_seconds        = 20
            timeout_seconds       = 5
          }

          resources {
            requests = {
              memory = "512Mi"
              cpu    = "250m"
            }
            limits = {
              memory = "1Gi"
              cpu    = "500m"
            }
          }
        }

        volume {
          name = "mysql-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.mysql_pvc.metadata[0].name
          }
        }
      }
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
  }

  wait_for_rollout = true

  depends_on = [kubernetes_persistent_volume_claim.mysql_pvc]
}

resource "kubernetes_service" "mysql" {
  metadata {
    name      = "mysql"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
  }
  spec {
    selector   = { app = "mysql" }
    cluster_ip = "None"
    port {
      port        = 3306
      target_port = 3306
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════
# Step 5: Redis — Deployment + Service
# ════════════════════════════════════════════════════════════════════════════
resource "kubernetes_deployment" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
    labels    = { app = "redis" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "redis" }
    }

    template {
      metadata {
        labels = { app = "redis" }
      }
      spec {
        enable_service_links = false
        container {
          name    = "redis"
          image   = "redis:7.0-alpine"
          command = ["redis-server", "--maxmemory", "256mb", "--maxmemory-policy", "allkeys-lru"]

          port {
            container_port = 6379
          }

          readiness_probe {
            exec {
              command = ["redis-cli", "ping"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            exec {
              command = ["redis-cli", "ping"]
            }
            initial_delay_seconds = 10
            period_seconds        = 20
          }

          resources {
            requests = {
              memory = "128Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "300Mi"
              cpu    = "200m"
            }
          }

          volume_mount {
            name       = "redis-data"
            mount_path = "/data"
          }
        }

        volume {
          name = "redis-data"
          empty_dir {}
        }
      }
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
  }

  wait_for_rollout = true
}

resource "kubernetes_service" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
  }
  spec {
    selector = { app = "redis" }
    port {
      port        = 6379
      target_port = 6379
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════
# Step 6: Application Services
# ════════════════════════════════════════════════════════════════════════════

# ── Product Service (Java 17 / Spring Boot — port 8081) ──
resource "kubernetes_deployment" "product_service" {
  metadata {
    name      = "product-service"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
    labels    = { app = "product-service", tier = "backend" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "product-service" }
    }

    template {
      metadata {
        labels = { app = "product-service", tier = "backend" }
      }
      spec {
        enable_service_links = false

        volume {
          name = "s247agent"
          empty_dir {}
        }

        volume {
          name = "chaos-config"
          host_path {
            path = "/var/site24x7-labs/faults"
            type = "DirectoryOrCreate"
          }
        }

        init_container {
          name              = "s247-java-agent"
          image             = "site24x7/apminsight-javaagent:latest"
          image_pull_policy = "IfNotPresent"
          command           = ["sh", "-c", "cp -r /opt/site24x7/. /home/apm && chmod -R 777 /home/apm"]
          volume_mount {
            name       = "s247agent"
            mount_path = "/home/apm"
          }
        }

        container {
          name              = "product-service"
          image_pull_policy = "Always"
          image             = "${var.docker_registry}/product-service:${var.image_tag}"

          port {
            container_port = 8081
          }

          volume_mount {
            name       = "s247agent"
            mount_path = "/home/apm"
          }

          volume_mount {
            name       = "chaos-config"
            mount_path = "/var/site24x7-labs/faults"
          }

          env {
            name  = "JAVA_TOOL_OPTIONS"
            value = "-javaagent:/home/apm/apminsight-javaagent.jar -Dapminsight.application.name=ZylkerKart-ProductService"
          }
          env {
            name = "S247_LICENSE_KEY"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "S247_LICENSE_KEY"
              }
            }
          }
          env {
            name  = "SERVER_PORT"
            value = "8081"
          }
          env {
            name  = "SPRING_DATASOURCE_URL"
            value = "jdbc:mysql://mysql:3306/db_product?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"
          }
          env {
            name = "SPRING_DATASOURCE_USERNAME"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "DB_USER"
              }
            }
          }
          env {
            name = "SPRING_DATASOURCE_PASSWORD"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "MYSQL_ROOT_PASSWORD"
              }
            }
          }
          env {
            name  = "REDIS_HOST"
            value = "redis"
          }
          env {
            name  = "REDIS_PORT"
            value = "6379"
          }
          env {
            name  = "CHAOS_SDK_ENABLED"
            value = "true"
          }
          env {
            name  = "CHAOS_SDK_APP_NAME"
            value = "product-service"
          }
          env {
            name  = "CHAOS_SDK_CONFIG_DIR"
            value = "/var/site24x7-labs/faults"
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8081
            }
            initial_delay_seconds = 60
            period_seconds        = 10
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8081
            }
            initial_delay_seconds = 90
            period_seconds        = 20
          }
          resources {
            requests = { memory = "512Mi", cpu = "200m" }
            limits   = { memory = "1Gi", cpu = "500m" }
          }
        }
      }
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
  }

  wait_for_rollout = false

  depends_on = [
    kubernetes_deployment.mysql,
    kubernetes_service.mysql,
    kubernetes_deployment.redis,
    kubernetes_service.redis,
  ]
}

resource "kubernetes_service" "product_service" {
  metadata {
    name      = "product-service"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
  }
  spec {
    selector = { app = "product-service" }
    port {
      port        = 8081
      target_port = 8081
    }
  }
}

# ── Order Service (Node.js 18 / Express — port 8082) ──
resource "kubernetes_deployment" "order_service" {
  metadata {
    name      = "order-service"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
    labels    = { app = "order-service", tier = "backend" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "order-service" }
    }

    template {
      metadata {
        labels = { app = "order-service", tier = "backend" }
      }
      spec {
        enable_service_links = false

        volume {
          name = "s247agent"
          empty_dir {}
        }

        volume {
          name = "chaos-config"
          host_path {
            path = "/var/site24x7-labs/faults"
            type = "DirectoryOrCreate"
          }
        }

        init_container {
          name              = "s247-nodejs-agent"
          image             = "site24x7/apminsight-nodejsagent:latest"
          image_pull_policy = "IfNotPresent"
          command           = ["sh", "-c", "cp -r /opt/site24x7/. /apm && chmod -R 755 /apm"]
          volume_mount {
            name       = "s247agent"
            mount_path = "/apm"
          }
        }

        container {
          name              = "order-service"
          image_pull_policy = "Always"
          image             = "${var.docker_registry}/order-service:${var.image_tag}"

          port {
            container_port = 8082
          }

          volume_mount {
            name       = "s247agent"
            mount_path = "/apm"
          }

          volume_mount {
            name       = "chaos-config"
            mount_path = "/var/site24x7-labs/faults"
          }

          env {
            name  = "NODE_OPTIONS"
            value = "--require /apm/node_modules/apminsight"
          }
          env {
            name = "APMINSIGHT_LICENSE_KEY"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "S247_LICENSE_KEY"
              }
            }
          }
          env {
            name  = "APMINSIGHT_APP_NAME"
            value = "ZylkerKart-OrderService"
          }
          env {
            name  = "APMINSIGHT_APP_PORT"
            value = "8082"
          }
          env {
            name  = "PORT"
            value = "8082"
          }
          env {
            name  = "DB_HOST"
            value = "mysql"
          }
          env {
            name  = "DB_PORT"
            value = "3306"
          }
          env {
            name = "DB_USER"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "DB_USER"
              }
            }
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "MYSQL_ROOT_PASSWORD"
              }
            }
          }
          env {
            name  = "DB_NAME"
            value = "db_order"
          }
          env {
            name  = "REDIS_HOST"
            value = "redis"
          }
          env {
            name  = "REDIS_PORT"
            value = "6379"
          }
          env {
            name = "PAYMENT_SERVICE_URL"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "PAYMENT_SERVICE_URL"
              }
            }
          }
          env {
            name = "AUTH_SERVICE_URL"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "AUTH_SERVICE_URL"
              }
            }
          }
          env {
            name  = "CHAOS_SDK_ENABLED"
            value = "true"
          }
          env {
            name  = "CHAOS_SDK_APP_NAME"
            value = "order-service"
          }
          env {
            name  = "CHAOS_SDK_CONFIG_DIR"
            value = "/var/site24x7-labs/faults"
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8082
            }
            initial_delay_seconds = 60
            period_seconds        = 10
            failure_threshold     = 30
            timeout_seconds       = 5

          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8082
            }
            initial_delay_seconds = 60
            period_seconds        = 20
            failure_threshold     = 10
            timeout_seconds       = 5
          }
          resources {
            requests = { memory = "192Mi", cpu = "100m" }
            limits   = { memory = "512Mi", cpu = "300m" }
          }
        }
      }
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
  }

  wait_for_rollout = false

  depends_on = [
    kubernetes_deployment.mysql,
    kubernetes_service.mysql,
    kubernetes_deployment.redis,
    kubernetes_service.redis,
  ]
}

resource "kubernetes_service" "order_service" {
  metadata {
    name      = "order-service"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
  }
  spec {
    selector = { app = "order-service" }
    port {
      port        = 8082
      target_port = 8082
    }
  }
}

# ── Search Service (Go 1.21 / Gin — port 8083) ──
resource "kubernetes_deployment" "search_service" {
  metadata {
    name      = "search-service"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
    labels    = { app = "search-service", tier = "backend" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "search-service" }
    }

    template {
      metadata {
        labels = { app = "search-service", tier = "backend" }
      }
      spec {
        enable_service_links = false

        volume {
          name = "chaos-config"
          host_path {
            path = "/var/site24x7-labs/faults"
            type = "DirectoryOrCreate"
          }
        }



        init_container {
          name              = "copy-binary"
          image_pull_policy = "Always"
          image             = "${var.docker_registry}/search-service:${var.image_tag}"
          command           = ["cp", "/app/search-service", "/apm-bin/search-service"]
          volume_mount {
            name       = "apm-binaries"
            mount_path = "/apm-bin"
          }
        }

        container {
          name              = "search-service"
          image_pull_policy = "Always"
          image             = "${var.docker_registry}/search-service:${var.image_tag}"
          command           = ["/apm-bin/search-service"]

          port {
            container_port = 8083
          }

          env {
            name  = "PORT"
            value = "8083"
          }
          env {
            name  = "DB_HOST"
            value = "mysql"
          }
          env {
            name  = "DB_PORT"
            value = "3306"
          }
          env {
            name = "DB_USER"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "DB_USER"
              }
            }
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "MYSQL_ROOT_PASSWORD"
              }
            }
          }
          env {
            name  = "DB_NAME"
            value = "db_search"
          }
          env {
            name  = "REDIS_HOST"
            value = "redis"
          }
          env {
            name  = "REDIS_PORT"
            value = "6379"
          }

          volume_mount {
            name       = "apm-binaries"
            mount_path = "/apm-bin"
          }
          volume_mount {
            name       = "chaos-config"
            mount_path = "/var/site24x7-labs/faults"
          }
          env {
            name  = "CHAOS_SDK_ENABLED"
            value = "true"
          }
          env {
            name  = "CHAOS_SDK_APP_NAME"
            value = "search-service"
          }
          env {
            name  = "CHAOS_SDK_CONFIG_DIR"
            value = "/var/site24x7-labs/faults"
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8083
            }
            initial_delay_seconds = 60
            period_seconds        = 10
            failure_threshold     = 30
            timeout_seconds       = 5
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8083
            }
            initial_delay_seconds = 60
            period_seconds        = 20
            failure_threshold     = 30
            timeout_seconds       = 5
          }
          resources {
            requests = { memory = "96Mi", cpu = "50m" }
            limits   = { memory = "320Mi", cpu = "200m" }
          }
        }

        volume {
          name = "apm-binaries"
          host_path {
            path = "/var/lib/apm-binaries"
            type = "DirectoryOrCreate"
          }
        }
      }
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
  }

  wait_for_rollout = false

  depends_on = [
    kubernetes_deployment.mysql,
    kubernetes_service.mysql,
    kubernetes_deployment.redis,
    kubernetes_service.redis,
  ]
}

resource "kubernetes_service" "search_service" {
  metadata {
    name      = "search-service"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
  }
  spec {
    selector = { app = "search-service" }
    port {
      port        = 8083
      target_port = 8083
    }
  }
}

# ── Payment Service (Python 3.11 / FastAPI — port 8084) ──
resource "kubernetes_deployment" "payment_service" {
  metadata {
    name      = "payment-service"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
    labels    = { app = "payment-service", tier = "backend" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "payment-service" }
    }

    template {
      metadata {
        labels = { app = "payment-service", tier = "backend" }
      }
      spec {
        enable_service_links = false

        volume {
          name = "s247agent"
          empty_dir {}
        }

        volume {
          name = "apm-data"
          empty_dir {}
        }

        volume {
          name = "chaos-config"
          host_path {
            path = "/var/site24x7-labs/faults"
            type = "DirectoryOrCreate"
          }
        }


        init_container {
          name    = "s247-python-agent"
          image   = "site24x7/apminsight-pythonagent:latest"
          command = ["sh", "-c", "cp -r /opt/site24x7/. /home/apm && chmod -R 777 /home/apm"]
          volume_mount {
            name       = "s247agent"
            mount_path = "/home/apm"
          }
        }

        container {
          name              = "payment-service"
          image_pull_policy = "Always"
          image             = "${var.docker_registry}/payment-service:${var.image_tag}"
          command           = ["/bin/sh", "-c", "/home/apm/agent_start.sh"]

          port {
            container_port = 8084
          }

          volume_mount {
            name       = "s247agent"
            mount_path = "/home/apm"
          }
          volume_mount {
            name       = "apm-data"
            mount_path = "/app/apminsightdata"
          }
          volume_mount {
            name       = "chaos-config"
            mount_path = "/var/site24x7-labs/faults"
          }

          env {
            name  = "APP_RUN_COMMAND"
            value = "uvicorn app.main:app --host 0.0.0.0 --port 8084 --workers 2"
          }
          env {
            name  = "APM_APP_NAME"
            value = "ZylkerKart-PaymentService"
          }
          env {
            name = "S247_LICENSE_KEY"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "S247_LICENSE_KEY"
              }
            }
          }
          env {
            name  = "PORT"
            value = "8084"
          }
          env {
            name  = "DB_HOST"
            value = "mysql"
          }
          env {
            name  = "DB_PORT"
            value = "3306"
          }
          env {
            name = "DB_USER"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "DB_USER"
              }
            }
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "MYSQL_ROOT_PASSWORD"
              }
            }
          }
          env {
            name  = "DB_NAME"
            value = "db_payment"
          }
          env {
            name  = "REDIS_HOST"
            value = "redis"
          }
          env {
            name  = "REDIS_PORT"
            value = "6379"
          }
          env {
            name  = "CHAOS_SDK_ENABLED"
            value = "true"
          }
          env {
            name  = "CHAOS_SDK_APP_NAME"
            value = "payment-service"
          }
          env {
            name  = "CHAOS_SDK_CONFIG_DIR"
            value = "/var/site24x7-labs/faults"
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8084
            }
            initial_delay_seconds = 60
            period_seconds        = 10
            failure_threshold     = 30
            timeout_seconds       = 5
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8084
            }
            initial_delay_seconds = 60
            period_seconds        = 20
            failure_threshold     = 10
          }
          resources {
            requests = { memory = "192Mi", cpu = "100m" }
            limits   = { memory = "512Mi", cpu = "300m" }
          }
        }
      }
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
  }

  wait_for_rollout = false

  depends_on = [
    kubernetes_deployment.mysql,
    kubernetes_service.mysql,
    kubernetes_deployment.redis,
    kubernetes_service.redis,
  ]
}

resource "kubernetes_service" "payment_service" {
  metadata {
    name      = "payment-service"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
  }
  spec {
    selector = { app = "payment-service" }
    port {
      port        = 8084
      target_port = 8084
    }
  }
}

# ── Auth Service (C# / .NET 8 — port 8085) ──
resource "kubernetes_deployment" "auth_service" {
  metadata {
    name      = "auth-service"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
    labels    = { app = "auth-service", tier = "backend" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "auth-service" }
    }

    template {
      metadata {
        labels = { app = "auth-service", tier = "backend" }
      }
      spec {
        enable_service_links = false

        volume {
          name = "s247dotnetagent"
          empty_dir {}
        }

        volume {
          name = "chaos-config"
          host_path {
            path = "/var/site24x7-labs/faults"
            type = "DirectoryOrCreate"
          }
        }


        init_container {
          name              = "s247-dotnet-agent"
          image             = "site24x7/apminsight-dotnetagent:latest"
          image_pull_policy = "IfNotPresent"
          command           = ["sh", "-c", "cp -r /opt/site24x7/APMDotNetAgent/. /home/APMDotNetAgent/ && chmod -R 777 /home/APMDotNetAgent"]
          volume_mount {
            name       = "s247dotnetagent"
            mount_path = "/home/APMDotNetAgent"
          }
        }

        container {
          name              = "auth-service"
          image_pull_policy = "Always"
          image             = "${var.docker_registry}/auth-service:${var.image_tag}"

          port {
            container_port = 8085
          }

          volume_mount {
            name       = "s247dotnetagent"
            mount_path = "/home/APMDotNetAgent"
          }
          volume_mount {
            name       = "chaos-config"
            mount_path = "/var/site24x7-labs/faults"
          }

          env {
            name = "S247_LICENSE_KEY"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "S247_LICENSE_KEY"
              }
            }
          }
          env {
            name  = "CORECLR_ENABLE_PROFILING"
            value = "1"
          }
          env {
            name  = "CORECLR_PROFILER"
            value = "{9D363A5F-ED5F-4AAC-B456-75AFFA6AA0C8}"
          }
          env {
            name  = "DOTNETCOREAGENT_HOME"
            value = "/home/APMDotNetAgent"
          }
          env {
            name  = "CORECLR_PROFILER_PATH_64"
            value = "/home/APMDotNetAgent/x64/libClrProfilerAgent.so"
          }
          env {
            name  = "CORECLR_PROFILER_PATH_32"
            value = "/home/APMDotNetAgent/x86/libClrProfilerAgent.so"
          }
          env {
            name  = "DOTNET_STARTUP_HOOKS"
            value = "/home/APMDotNetAgent/netstandard2.0/DotNetAgent.Loader.dll"
          }
          env {
            name  = "MANAGEENGINE_COMMUNICATION_MODE"
            value = "direct"
          }
          env {
            name  = "SITE24X7_APP_NAME"
            value = "ZylkerKart-AuthService"
          }
          env {
            name  = "PORT"
            value = "8085"
          }
          env {
            name  = "DB_HOST"
            value = "mysql"
          }
          env {
            name  = "DB_PORT"
            value = "3306"
          }
          env {
            name = "DB_USER"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "DB_USER"
              }
            }
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "MYSQL_ROOT_PASSWORD"
              }
            }
          }
          env {
            name  = "DB_NAME"
            value = "db_auth"
          }
          env {
            name  = "ConnectionStrings__DefaultConnection"
            value = "Server=mysql;Port=3306;Database=db_auth;Uid=root;Pwd=${var.mysql_root_password};"
          }
          env {
            name = "JWT_SECRET"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }
          env {
            name  = "JWT_EXPIRY_MINUTES"
            value = "15"
          }
          env {
            name  = "JWT_REFRESH_EXPIRY_DAYS"
            value = "7"
          }
          env {
            name  = "CHAOS_SDK_ENABLED"
            value = "true"
          }
          env {
            name  = "CHAOS_SDK_APP_NAME"
            value = "auth-service"
          }
          env {
            name  = "CHAOS_SDK_CONFIG_DIR"
            value = "/var/site24x7-labs/faults"
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8085
            }
            initial_delay_seconds = 20
            period_seconds        = 10
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8085
            }
            initial_delay_seconds = 30
            period_seconds        = 20
          }
          resources {
            requests = { memory = "192Mi", cpu = "100m" }
            limits   = { memory = "512Mi", cpu = "300m" }
          }
        }
      }
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
  }

  wait_for_rollout = false

  depends_on = [
    kubernetes_deployment.mysql,
    kubernetes_service.mysql,
    kubernetes_deployment.redis,
    kubernetes_service.redis,
  ]
}

resource "kubernetes_service" "auth_service" {
  metadata {
    name      = "auth-service"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
  }
  spec {
    selector = { app = "auth-service" }
    port {
      port        = 8085
      target_port = 8085
    }
  }
}

# ── Storefront BFF (Java 17 / Spring Boot 3.2 — port 80) ──
resource "kubernetes_deployment" "storefront" {
  metadata {
    name      = "storefront"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
    labels    = { app = "storefront", tier = "frontend" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "storefront" }
    }

    template {
      metadata {
        labels = { app = "storefront", tier = "frontend" }
      }
      spec {
        enable_service_links = false

        volume {
          name = "s247agent"
          empty_dir {}
        }

        volume {
          name = "chaos-config"
          host_path {
            path = "/var/site24x7-labs/faults"
            type = "DirectoryOrCreate"
          }
        }

        init_container {
          name              = "s247-java-agent"
          image             = "site24x7/apminsight-javaagent:latest"
          image_pull_policy = "IfNotPresent"
          command = [
            "sh", "-c",
            "cp -r /opt/site24x7/. /home/apm && chmod -R 777 /home/apm"
          ]
          volume_mount {
            name       = "s247agent"
            mount_path = "/home/apm"
          }
        }

        container {
          name              = "storefront"
          image_pull_policy = "Always"
          image             = "${var.docker_registry}/storefront:${var.image_tag}"

          port {
            container_port = 8080
          }

          volume_mount {
            name       = "s247agent"
            mount_path = "/home/apm"
          }
          volume_mount {
            name       = "chaos-config"
            mount_path = "/var/site24x7-labs/faults"
          }

          env {
            name  = "JAVA_TOOL_OPTIONS"
            value = "-javaagent:/home/apm/apminsight-javaagent.jar -Dapminsight.application.name=ZylkerKart-Storefront"
          }
          env {
            name  = "SERVER_PORT"
            value = "8080"
          }
          env {
            name = "S247_LICENSE_KEY"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "S247_LICENSE_KEY"
              }
            }
          }
          env {
            name = "REDIS_HOST"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "REDIS_HOST"
              }
            }
          }
          env {
            name = "REDIS_PORT"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "REDIS_PORT"
              }
            }
          }
          env {
            name = "PRODUCT_SERVICE_URL"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "PRODUCT_SERVICE_URL"
              }
            }
          }
          env {
            name = "ORDER_SERVICE_URL"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "ORDER_SERVICE_URL"
              }
            }
          }
          env {
            name = "SEARCH_SERVICE_URL"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "SEARCH_SERVICE_URL"
              }
            }
          }
          env {
            name = "PAYMENT_SERVICE_URL"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "PAYMENT_SERVICE_URL"
              }
            }
          }
          env {
            name = "AUTH_SERVICE_URL"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "AUTH_SERVICE_URL"
              }
            }
          }
          env {
            name  = "CHAOS_SDK_ENABLED"
            value = "true"
          }
          env {
            name  = "CHAOS_SDK_APP_NAME"
            value = "storefront"
          }
          env {
            name  = "CHAOS_SDK_CONFIG_DIR"
            value = "/var/site24x7-labs/faults"
          }

          startup_probe {
            http_get {
              path = "/actuator/health"
              port = 8080
            }
            initial_delay_seconds = 60
            period_seconds        = 10
            failure_threshold     = 30
            timeout_seconds       = 5
          }
          readiness_probe {
            http_get {
              path = "/actuator/health"
              port = 8080
            }
            initial_delay_seconds = 0
            period_seconds        = 10
            failure_threshold     = 3
            timeout_seconds       = 5
          }
          liveness_probe {
            http_get {
              path = "/actuator/health"
              port = 8080
            }
            initial_delay_seconds = 0
            period_seconds        = 20
            failure_threshold     = 3
            timeout_seconds       = 5
          }
          resources {
            requests = { memory = "256Mi", cpu = "100m" }
            limits   = { memory = "512Mi", cpu = "400m" }
          }
        }
      }
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
  }

  wait_for_rollout = false

  depends_on = [
    kubernetes_deployment.mysql,
    kubernetes_service.mysql,
    kubernetes_deployment.redis,
    kubernetes_service.redis,
  ]
}

resource "kubernetes_service" "storefront" {
  metadata {
    name      = "storefront"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
  }
  spec {
    type     = "LoadBalancer"
    selector = { app = "storefront" }
    port {
      port        = 80
      target_port = 8080
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════
# Step 7: Ingress (NGINX Ingress Controller + Ingress resource)
# ════════════════════════════════════════════════════════════════════════════

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.9.1"
  timeout          = 600

  set {
    name  = "controller.replicaCount"
    value = "2"
  }

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  depends_on = [kubernetes_namespace.zylkerkart]
}

resource "kubernetes_ingress_v1" "zylkerkart" {
  metadata {
    name      = "zylkerkart-ingress"
    namespace = kubernetes_namespace.zylkerkart.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/proxy-body-size"       = "150m"
      "nginx.ingress.kubernetes.io/proxy-connect-timeout" = "30"
      "nginx.ingress.kubernetes.io/proxy-read-timeout"    = "60"
      "nginx.ingress.kubernetes.io/proxy-send-timeout"    = "60"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "storefront"
              port {
                number = 80
              }
            }
          }
        }
        path {
          path      = "/api/products"
          path_type = "Prefix"
          backend {
            service {
              name = "product-service"
              port {
                number = 8081
              }
            }
          }
        }
        path {
          path      = "/api/orders"
          path_type = "Prefix"
          backend {
            service {
              name = "order-service"
              port {
                number = 8082
              }
            }
          }
        }
        path {
          path      = "/api/cart"
          path_type = "Prefix"
          backend {
            service {
              name = "order-service"
              port {
                number = 8082
              }
            }
          }
        }
        path {
          path      = "/api/search"
          path_type = "Prefix"
          backend {
            service {
              name = "search-service"
              port {
                number = 8083
              }
            }
          }
        }
        path {
          path      = "/api/payments"
          path_type = "Prefix"
          backend {
            service {
              name = "payment-service"
              port {
                number = 8084
              }
            }
          }
        }
        path {
          path      = "/api/auth"
          path_type = "Prefix"
          backend {
            service {
              name = "auth-service"
              port {
                number = 8085
              }
            }
          }
        }
      }
    }

  }

  depends_on = [helm_release.ingress_nginx]
}


resource "kubernetes_config_map" "zylkerkart_config_monitoring" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name      = "zylkerkart-config"
    namespace = kubernetes_namespace.monitoring[0].metadata[0].name
  }

  data = {
    S247_LICENSE_KEY = var.site24x7_license_key
    # ... same keys as your zylkerkart namespace configmap
  }

  depends_on = [
    kubernetes_namespace.monitoring
  ]
}
# ════════════════════════════════════════════════════════════════════════════
# Step 8: Site24x7 Go APM DaemonSet (conditional on license key)
# ════════════════════════════════════════════════════════════════════════════
resource "kubernetes_config_map" "apm_apps_config" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name      = "apm-apps-config"
    namespace = kubernetes_namespace.monitoring[0].metadata[0].name
  }

  data = {
    go_apps = "ZylkerKart-SearchService=search-service:8083"
  }
}

resource "kubernetes_service_account" "apm_agent_sa" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name      = "apm-agent-sa"
    namespace = kubernetes_namespace.monitoring[0].metadata[0].name
  }
}

resource "kubernetes_cluster_role" "apm_agent_role" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name = "apm-agent-role"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "nodes", "namespaces"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "daemonsets"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "apm_agent_rolebinding" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name = "apm-agent-rolebinding"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.apm_agent_sa[0].metadata[0].name
    namespace = kubernetes_namespace.monitoring[0].metadata[0].name
  }
  role_ref {
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.apm_agent_role[0].metadata[0].name
    api_group = "rbac.authorization.k8s.io"
  }
}

resource "kubernetes_daemonset" "go_apm_exporter" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name      = "exporter-agent"
    namespace = kubernetes_namespace.monitoring[0].metadata[0].name
    labels    = { app = "site24x7-go-apm" }
  }

  spec {
    selector {
      match_labels = { app = "site24x7-go-apm" }
    }

    template {
      metadata {
        labels = { app = "site24x7-go-apm" }
      }
      spec {
        service_account_name = kubernetes_service_account.apm_agent_sa[0].metadata[0].name
        host_pid             = true

        container {
          name  = "exporter-agent"
          image = "site24x7/apminsight-go-agent:latest"
          # ════════════════════════════════════════════════════
          # FIX: Patch the install script template BEFORE
          # startup.sh runs, so the config is generated
          # with 127.0.0.1 from the start. Then run normally.
          # ════════════════════════════════════════════════════
          command = ["/bin/bash", "-c"]
          args = [<<-EOT
            # Run the normal startup in background
            /tmp/agent-installer/startup.sh &
            STARTUP_PID=$!

            # Wait for the config to be fully generated (check for license key, not placeholder)
            echo "[FIX] Waiting for Go agent config with real license key..."
            for i in $(seq 1 180); do
              if [ -f /opt/site24x7/apm-insight-go-agent/conf/configuration.json ]; then
                if grep -q "$$S247_LICENSE_KEY" /opt/site24x7/apm-insight-go-agent/conf/configuration.json; then
                  echo "[FIX] Config file ready with license key (waited $${i}s)"
                  break
                fi
              fi
              sleep 1
            done

            # Patch localhost to 127.0.0.1
            if [ -f /opt/site24x7/apm-insight-go-agent/conf/configuration.json ]; then
              sed -i 's/localhost/127.0.0.1/g' /opt/site24x7/apm-insight-go-agent/conf/configuration.json
              echo "[FIX] Patched config:"
              cat /opt/site24x7/apm-insight-go-agent/conf/configuration.json

              # Restart ONLY the Go agent (not the DataExporter)
              echo "[FIX] Restarting Go agent..."
              pkill -x apm-insight-go-agent 2>/dev/null || true
              sleep 3
              echo "[FIX] Done"
            fi

            # Keep container alive by waiting on startup.sh
            wait $STARTUP_PID
          EOT
          ]
          security_context {
            privileged  = true
            run_as_user = 0
          }

          env {
            name = "S247_LICENSE_KEY"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.zylkerkart_config.metadata[0].name
                key  = "S247_LICENSE_KEY"
              }
            }
          }
          env {
            name = "GO_APPS"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.apm_apps_config[0].metadata[0].name
                key  = "go_apps"
              }
            }
          }

          volume_mount {
            name       = "proc"
            mount_path = "/host/proc"
            read_only  = true
          }
          volume_mount {
            name       = "debug"
            mount_path = "/sys/kernel/debug"
          }
          volume_mount {
            name       = "bpf"
            mount_path = "/sys/fs/bpf"
          }
          volume_mount {
            name       = "sys"
            mount_path = "/sys"
          }
          volume_mount {
            name       = "apm-binaries"
            mount_path = "/var/lib/apm-binaries"
          }

          resources {
            requests = { memory = "128Mi", cpu = "100m" }
            limits   = { memory = "256Mi", cpu = "300m" }
          }
        }

        volume {
          name = "proc"
          host_path {
            path = "/proc"
          }
        }
        volume {
          name = "debug"
          host_path {
            path = "/sys/kernel/debug"
          }
        }
        volume {
          name = "bpf"
          host_path {
            path = "/sys/fs/bpf"
          }
        }
        volume {
          name = "sys"
          host_path {
            path = "/sys"
          }
        }
        volume {
          name = "apm-binaries"
          host_path {
            path = "/var/lib/apm-binaries"
            type = "DirectoryOrCreate"
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account.apm_agent_sa,
    kubernetes_cluster_role_binding.apm_agent_rolebinding,
  ]
}

# ════════════════════════════════════════════════════════════════════════════
# Step 9: Site24x7 Server Agent — FULL RBAC + Secret + DaemonSet
# ════════════════════════════════════════════════════════════════════════════
resource "kubernetes_secret" "site24x7_agent" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name      = "site24x7-agent"
    namespace = "default"
  }

  data = {
    KEY = var.site24x7_license_key
  }
}

resource "kubernetes_service_account" "site24x7" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name      = "site24x7"
    namespace = "default"
  }

  automount_service_account_token = true
}

resource "kubernetes_cluster_role" "site24x7" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name = "site24x7"
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps", "nodes", "pods", "services", "resourcequotas", "replicationcontrollers", "limitranges", "persistentvolumeclaims", "persistentvolumes", "namespaces", "endpoints", "componentstatuses", "events"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups     = [""]
    resources      = ["configmaps"]
    resource_names = ["site24x7"]
    verbs          = ["list", "watch", "get", "patch"]
  }
  rule {
    api_groups = ["extensions"]
    resources  = ["daemonsets", "deployments", "replicasets", "ingresses"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["daemonsets", "deployments", "replicasets", "statefulsets"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["events.k8s.io"]
    resources  = ["events"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["batch"]
    resources  = ["cronjobs", "jobs"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["certificates.k8s.io"]
    resources  = ["certificatesigningrequests"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["nodes/metrics", "nodes/stats", "nodes/metrics/cadvisor", "nodes/proxy"]
    verbs      = ["get"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    non_resource_urls = ["/metrics", "/healthz", "/livez"]
    verbs             = ["get"]
  }
}

resource "kubernetes_cluster_role_binding" "site24x7" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name = "site24x7"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.site24x7[0].metadata[0].name
    namespace = "default"
  }
  role_ref {
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.site24x7[0].metadata[0].name
    api_group = "rbac.authorization.k8s.io"
  }
}

resource "kubernetes_config_map" "site24x7" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name      = "site24x7"
    namespace = "default"
    labels = {
      "app.kubernetes.io/name"      = "site24x7"
      "app.kubernetes.io/component" = "agent"
      "app.kubernetes.io/owner"     = "site24x7"
    }
  }

  data = {
    NODE_AGENT_VERSION    = "22000"
    CLUSTER_AGENT_VERSION = "100"
    SETTINGS = jsonencode({
      kubernetes                       = "300"
      daemonsets                       = "300"
      deployments                      = "300"
      statefulsets                     = "300"
      pods                             = "300"
      nodes                            = "300"
      services                         = "300"
      replicasets                      = "900"
      ingresses                        = "300"
      jobs                             = "300"
      pv                               = "300"
      persistentvolumeclaim            = "300"
      componentstatuses                = "300"
      horizontalpodautoscalers         = "300"
      endpoints                        = "3600"
      namespaces                       = "300"
      eventcollector                   = "60"
      npcdatacollector                 = "300"
      npcdatacollector_discovery       = "900"
      resourcedependency               = "300"
      workloadsdatacollector           = "300"
      workloadsdatacollector_discovery = "900"
      clustermetricsaggregator         = "300"
      sidecarnpccollector              = "300"
      sidecarnpccollector_discovery    = "900"
      dcinit                           = "900"
      clusteragent                     = "1"
      ksm                              = "1"
      guidancemetrics                  = "20600"
      termination                      = "900"
      kubelet                          = "300"
      metadata                         = "20600"
      prometheus_integration           = "1"
      plugin_integration               = "1"
      database_integration             = "1"
      ksmprocessor                     = "1"
      kubeletdatapersistence           = "1"
      servicerelationdataprocessor     = "1"
      yamlfetcher                      = "60"
    })
    # ── ADDED: 1-minute high-frequency collection intervals ──────────────
    "1MIN" = jsonencode({
      Pods                     = "90"
      Nodes                    = "90"
      Namespaces               = "90"
      HorizontalPodAutoscalers = "-1"
      DaemonSets               = "90"
      Deployments              = "60"
      Endpoints                = "-1"
      ReplicaSets              = "-1"
      StatefulSets             = "90"
      Services                 = "-1"
      PV                       = "-1"
      PersistentVolumeClaims   = "-1"
      Jobs                     = "-1"
      Ingresses                = "-1"
    })
  }
}

resource "kubernetes_daemonset" "site24x7_agent" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name      = "site24x7-agent"
    namespace = "default"
  }

  spec {
    selector {
      match_labels = { app = "site24x7-agent" }
    }

    template {
      metadata {
        labels = { app = "site24x7-agent" }
      }
      spec {
        service_account_name = kubernetes_service_account.site24x7[0].metadata[0].name
        toleration {
          operator = "Exists"
        }
        node_selector = {
          "kubernetes.io/os" = "linux"
        }

        container {
          name              = "site24x7-agent"
          image             = "site24x7/docker-agent:release22000"
          image_pull_policy = "Always"

          security_context {
            run_as_user = 0
          }

          env {
            name = "KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.site24x7_agent[0].metadata[0].name
                key  = "KEY"
              }
            }
          }
          env {
            name  = "installer"
            value = "kubernetes"
          }
          env {
            name = "NODE_IP"
            value_from {
              field_ref {
                field_path = "status.hostIP"
              }
            }
          }
          env {
            name = "NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }
          env {
            name = "NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          volume_mount {
            name       = "procfs"
            mount_path = "/host/proc"
            read_only  = true
          }
          volume_mount {
            name       = "sysfs"
            mount_path = "/host/sys/"
            read_only  = true
          }
          volume_mount {
            name       = "varfs"
            mount_path = "/host/var/"
            read_only  = true
          }
          volume_mount {
            name       = "etcfs"
            mount_path = "/host/etc/"
            read_only  = true
          }
          volume_mount {
            name       = "site24x7-agent"
            mount_path = "/opt/site24x7/"
          }
          volume_mount {
            name       = "clusterconfig"
            mount_path = "/etc/site24x7/clusterconfig"
            read_only  = true
          }
        }

        volume {
          name = "procfs"
          host_path {
            path = "/proc"
          }
        }
        volume {
          name = "sysfs"
          host_path {
            path = "/sys/"
          }
        }
        volume {
          name = "varfs"
          host_path {
            path = "/var/"
          }
        }
        volume {
          name = "etcfs"
          host_path {
            path = "/etc/"
          }
        }
        volume {
          name = "site24x7-agent"
          empty_dir {}
        }
        volume {
          name = "clusterconfig"
          config_map {
            name     = kubernetes_config_map.site24x7[0].metadata[0].name
            optional = true
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_secret.site24x7_agent,
    kubernetes_service_account.site24x7,
    kubernetes_cluster_role_binding.site24x7,
    kubernetes_config_map.site24x7,
  ]
}

# ════════════════════════════════════════════════════════════════════════════
# ADDED: Kube State Metrics — RBAC + ServiceAccount + Service + Deployment
# ════════════════════════════════════════════════════════════════════════════
resource "kubernetes_service_account" "site24x7_ksm" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name      = "site24x7-kube-state-metrics"
    namespace = "default"
    labels = {
      "app.kubernetes.io/component" = "exporter"
      "app.kubernetes.io/name"      = "site24x7-kube-state-metrics"
      "app.kubernetes.io/version"   = "2.9.2"
    }
  }

  automount_service_account_token = false
}

resource "kubernetes_cluster_role" "site24x7_ksm" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name = "site24x7-kube-state-metrics"
    labels = {
      "app.kubernetes.io/component" = "exporter"
      "app.kubernetes.io/name"      = "site24x7-kube-state-metrics"
      "app.kubernetes.io/version"   = "2.9.2"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps", "secrets", "nodes", "pods", "services", "serviceaccounts", "resourcequotas", "replicationcontrollers", "limitranges", "persistentvolumeclaims", "persistentvolumes", "namespaces", "endpoints"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["statefulsets", "daemonsets", "deployments", "replicasets"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["batch"]
    resources  = ["cronjobs", "jobs"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["authentication.k8s.io"]
    resources  = ["tokenreviews"]
    verbs      = ["create"]
  }
  rule {
    api_groups = ["authorization.k8s.io"]
    resources  = ["subjectaccessreviews"]
    verbs      = ["create"]
  }
  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["certificates.k8s.io"]
    resources  = ["certificatesigningrequests"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["discovery.k8s.io"]
    resources  = ["endpointslices"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses", "volumeattachments"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["admissionregistration.k8s.io"]
    resources  = ["mutatingwebhookconfigurations", "validatingwebhookconfigurations"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["networkpolicies", "ingressclasses", "ingresses"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["clusterrolebindings", "clusterroles", "rolebindings", "roles"]
    verbs      = ["list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "site24x7_ksm" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name = "site24x7-kube-state-metrics"
    labels = {
      "app.kubernetes.io/component" = "exporter"
      "app.kubernetes.io/name"      = "site24x7-kube-state-metrics"
      "app.kubernetes.io/version"   = "2.9.2"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.site24x7_ksm[0].metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.site24x7_ksm[0].metadata[0].name
    namespace = "default"
  }
}

resource "kubernetes_service" "site24x7_ksm" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name      = "site24x7-kube-state-metrics"
    namespace = "default"
    labels = {
      "app.kubernetes.io/component" = "exporter"
      "app.kubernetes.io/name"      = "site24x7-kube-state-metrics"
      "app.kubernetes.io/version"   = "2.9.2"
    }
  }

  spec {
    cluster_ip = "None"
    selector   = { "app.kubernetes.io/name" = "site24x7-kube-state-metrics" }

    port {
      name        = "http-metrics"
      port        = 8080
      target_port = "http-metrics"
    }
    port {
      name        = "telemetry"
      port        = 8081
      target_port = "telemetry"
    }
  }
}

resource "kubernetes_deployment" "site24x7_ksm" {
  count = local.enable_apm ? 1 : 0

  metadata {
    name      = "site24x7-kube-state-metrics"
    namespace = "default"
    labels = {
      "app.kubernetes.io/component" = "exporter"
      "app.kubernetes.io/name"      = "site24x7-kube-state-metrics"
      "app.kubernetes.io/version"   = "2.9.2"
      "app"                         = "site24x7-kube-state-metrics"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { "app.kubernetes.io/name" = "site24x7-kube-state-metrics" }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/component" = "exporter"
          "app.kubernetes.io/name"      = "site24x7-kube-state-metrics"
          "app.kubernetes.io/version"   = "2.9.2"
          "app"                         = "site24x7-kube-state-metrics"
        }
      }

      spec {
        automount_service_account_token = true
        service_account_name            = kubernetes_service_account.site24x7_ksm[0].metadata[0].name

        node_selector = { "kubernetes.io/os" = "linux" }

        toleration {
          operator = "Exists"
        }

        container {
          name              = "site24x7-kube-state-metrics"
          image             = "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.9.2"
          image_pull_policy = "IfNotPresent"

          port {
            name           = "http-metrics"
            container_port = 8080
          }
          port {
            name           = "telemetry"
            container_port = 8081
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 5
            timeout_seconds       = 5
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 8081
            }
            initial_delay_seconds = 5
            timeout_seconds       = 5
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 65534
            capabilities {
              drop = ["ALL"]
            }
            seccomp_profile {
              type = "RuntimeDefault"
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account.site24x7_ksm,
    kubernetes_cluster_role_binding.site24x7_ksm,
  ]
}

# ──────────────────────────────────────────────
# Gate resource: signals that ALL k8s is ready
# ──────────────────────────────────────────────
resource "terraform_data" "k8s_ready" {
  input = "all-k8s-deployed"

  depends_on = [
    kubernetes_deployment.order_service,
    kubernetes_deployment.storefront,
    kubernetes_deployment.search_service,
    kubernetes_deployment.product_service,
    kubernetes_deployment.payment_service,
    kubernetes_deployment.auth_service,
  ]
}
