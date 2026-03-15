resource "kubernetes_namespace" "site24x7_labs" {
  metadata {
    name = "site24x7-labs"
  }
}

resource "helm_release" "site24x7_labs" {
  name             = "site24x7-labs"
  chart            = "./site24x7-labs"
  namespace        = kubernetes_namespace.site24x7_labs.metadata[0].name
  create_namespace = false
  timeout          = 900
  wait             = true
  atomic           = true

  depends_on = [terraform_data.k8s_ready]


  set {
    name  = "image.server.repository"
    value = "impazhani/site24x7-labs-server"
  }
  set {
    name  = "image.server.tag"
    value = "dev"
  }
  set {
    name  = "image.server.pullPolicy"
    value = "Always"
  }
  set {
    name  = "image.agent.repository"
    value = "impazhani/site24x7-labs-agent"
  }
  set {
    name  = "image.agent.tag"
    value = "dev"
  }
  set {
    name  = "image.agent.pullPolicy"
    value = "Always"
  }
  set {
    name  = "image.frontend.repository"
    value = "impazhani/site24x7-labs-frontend"
  }
  set {
    name  = "image.frontend.tag"
    value = "dev"
  }
  set {
    name  = "image.frontend.pullPolicy"
    value = "Always"
  }
  set {
    name  = "auth.jwtSecret"
    value = "site24x7-labs-jwt-secret-2024"
  }
  set {
    name  = "auth.adminPassword"
    value = "admin123"
  }
  set {
    name  = "auth.adminEmail"
    value = "admin@site24x7labs.local"
  }
  set {
    name  = "auth.agentToken"
    value = "s24x7_at_db65e96f921cbd5f8f5c0688280742d490472f5e6a30c4c1c57b4bbe5540d38d"
  }
  set {
    name  = "postgresql.auth.password"
    value = "pgpass2024"
  }
  # Replaced 3 storageClass blocks with 1 global one
  set {
    name  = "storageClass"
    value = local.storage_class
  }
  set {
    name  = "cors.allowedOrigins"
    value = "*"
  }
  set {
    name  = "serviceFrontend.type"
    value = "LoadBalancer"
  }
  set {
    name  = "logging.level"
    value = "debug"
  }
}

# ──────────────────────────────────────────────
# Post-deploy: read the frontend LoadBalancer IP
# ──────────────────────────────────────────────
data "kubernetes_service" "site24x7_labs_frontend" {
  metadata {
    name      = "site24x7-labs-frontend"
    namespace = kubernetes_namespace.site24x7_labs.metadata[0].name
  }

  depends_on = [helm_release.site24x7_labs]
}

locals {
  site24x7_labs_frontend_ip = try(
    data.kubernetes_service.site24x7_labs_frontend.status[0].load_balancer[0].ingress[0].ip,
    data.kubernetes_service.site24x7_labs_frontend.status[0].load_balancer[0].ingress[0].hostname,
    "pending"
  )
  site24x7_labs_env_name = var.cloud_provider == "azure" ? "aks-${var.azure_location}" : "eks-${var.aws_region}"
}

# ──────────────────────────────────────────────
# Post-deploy: login → create env → patch secret
#              → restart agent DaemonSet
# ──────────────────────────────────────────────
resource "terraform_data" "site24x7_labs_env_setup" {

  input = {
    frontend_ip = local.site24x7_labs_frontend_ip
    env_name    = local.site24x7_labs_env_name
    namespace   = kubernetes_namespace.site24x7_labs.metadata[0].name
    script_dir  = "${abspath(path.module)}\\scripts"
  }

  provisioner "local-exec" {
    command = "powershell -NoProfile -File ${abspath(path.module)}\\scripts\\setup_site24x7_labs_env.ps1 -FrontendIP ${local.site24x7_labs_frontend_ip} -EnvironmentName ${local.site24x7_labs_env_name} -Namespace ${kubernetes_namespace.site24x7_labs.metadata[0].name}"
  }

  depends_on = [helm_release.site24x7_labs]
}
