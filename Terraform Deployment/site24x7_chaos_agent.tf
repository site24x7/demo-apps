# =============================================================================
# Locals
# =============================================================================

locals {
  # --- Log file so we can see output even when Terraform suppresses it ---
  setup_log_file = "${path.module}/.site24x7_env_setup.log"

  # --- Output file for env setup results ---
  env_output_file = "${path.module}/.site24x7_env_output.json"

  # --- Kubeconfig context command per cloud provider ---
  kubeconfig_command = var.cloud_provider == "azure" ? join(" ", [
    "az", "aks", "get-credentials",
    "--resource-group", var.azure_resource_group_name,
    "--name", var.cluster_name,
    "--overwrite-existing"
  ]) : join(" ", [
    "aws", "eks", "update-kubeconfig",
    "--region", var.aws_region,
    "--name", var.cluster_name
  ])
}

# =============================================================================
# Step 1 — Setup environment & obtain token + environment ID
#           (PowerShell only — no Kubernetes resources here)
# =============================================================================

resource "terraform_data" "site24x7_env_setup" {
  depends_on = [terraform_data.k8s_ready]

  triggers_replace = [timestamp()]

  input = {
    server           = var.site24x7_server
    environment_name = var.site24x7_environment_name
    admin_email      = var.site24x7_admin_email
    admin_password   = var.site24x7_admin_password
    namespace        = var.site24x7_namespace
    output_file      = local.env_output_file
  }

  provisioner "local-exec" {
    interpreter = ["powershell", "-NoProfile", "-Command"]

    command = <<-EOT
      $ErrorActionPreference = "Stop"
      $logFile = "${local.setup_log_file}"
      $outputFile = "${local.env_output_file}"

      function Log($msg) {
        $ts = Get-Date -Format "HH:mm:ss"
        $line = "[$ts] $msg"
        Write-Host $line
        Add-Content -Path $logFile -Value $line
      }

      Set-Content -Path $logFile -Value "=== Site24x7 Env Setup Log ===" -Force

      # ── Step 1: Set Kubernetes context ──
      Log "Step 1 — Setting kubeconfig context (${var.cloud_provider})..."
      ${local.kubeconfig_command}
      if ($LASTEXITCODE -ne 0) {
        Log "FAILED: kubeconfig context setup failed with exit code $LASTEXITCODE"
        exit 1
      }
      Log "Step 1 — kubeconfig context set successfully."

      # ── Step 2: Verify connectivity ──
      Log "Step 2 — Verifying cluster connectivity..."
      kubectl cluster-info
      if ($LASTEXITCODE -ne 0) {
        Log "FAILED: Cannot reach Kubernetes cluster"
        exit 1
      }
      Log "Step 2 — Cluster is reachable."

      # ── Step 3: Login to Site24x7 Labs API ──
      Log "Step 3 — Logging in to Site24x7 Labs..."
      Log "  Server:          ${var.site24x7_server}"
      Log "  EnvironmentName: ${var.site24x7_environment_name}"
      Log "  Namespace:       ${var.site24x7_namespace}"
      Log "  AdminEmail:      ${var.site24x7_admin_email}"

      $baseUrl = "http://${var.site24x7_server}"
      $loginBody = @{ email = "${var.site24x7_admin_email}"; password = "${var.site24x7_admin_password}" } | ConvertTo-Json

      Log "  Waiting for API at $baseUrl ..."
      $maxRetries = 20
      $retrySec   = 15
      $loginResponse = $null

      for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
          $loginResponse = Invoke-RestMethod -Uri "$baseUrl/api/v1/auth/login" `
            -Method POST -ContentType "application/json" -Body $loginBody -TimeoutSec 10
          Log "  API reachable! (attempt $attempt/$maxRetries)"
          break
        } catch {
          if ($attempt -eq $maxRetries) {
            Log "FAILED: API not reachable after $maxRetries attempts"
            try { kubectl get pods -n "${var.site24x7_namespace}" -o wide 2>&1 | ForEach-Object { Log "  $_" } } catch {}
            try { kubectl get svc -n "${var.site24x7_namespace}" 2>&1 | ForEach-Object { Log "  $_" } } catch {}
            exit 1
          }
          Log "  Attempt $attempt/$maxRetries failed: $($_.Exception.Message). Retrying in $${retrySec}s..."
          Start-Sleep -Seconds $retrySec
        }
      }

      # Extract JWT
      $jwt = $null
      if ($loginResponse.data -and $loginResponse.data.access_token) { $jwt = $loginResponse.data.access_token }
      elseif ($loginResponse.token)        { $jwt = $loginResponse.token }
      elseif ($loginResponse.access_token) { $jwt = $loginResponse.access_token }

      if (-not $jwt) {
        Log "FAILED: No token in login response"
        Log "  Response: $($loginResponse | ConvertTo-Json -Compress -Depth 5)"
        exit 1
      }
      Log "  Login successful, JWT obtained."

      # ── Step 4: Create or find environment ──
      Log "Step 4 — Creating/finding environment '${var.site24x7_environment_name}'..."
      $headers = @{ "Authorization" = "Bearer $jwt"; "Content-Type" = "application/json" }
      $envBody = @{ name = "${var.site24x7_environment_name}"; type = "kubernetes" } | ConvertTo-Json
      $envResponse = $null

      try {
        $envResponse = Invoke-RestMethod -Uri "$baseUrl/api/v1/environments/" `
          -Method POST -Headers $headers -Body $envBody -TimeoutSec 10
        Log "  Environment created."
      } catch {
        Log "  Create returned error (may already exist): $($_.Exception.Message)"
        Log "  Fetching existing environments..."
        $allEnvs = Invoke-RestMethod -Uri "$baseUrl/api/v1/environments/" -Method GET -Headers $headers -TimeoutSec 10
        $envList = if ($allEnvs.data) { $allEnvs.data } else { @($allEnvs) }
        $envResponse = $envList | Where-Object { $_.name -eq "${var.site24x7_environment_name}" } | Select-Object -First 1
        if (-not $envResponse) {
          Log "FAILED: Could not create or find environment"
          exit 1
        }
        Log "  Found existing environment."
      }

      # Extract agent_token and environment_id
      $agentToken = $null
      if ($envResponse.data -and $envResponse.data.agent_token)   { $agentToken = $envResponse.data.agent_token }
      elseif ($envResponse.agent_token)                            { $agentToken = $envResponse.agent_token }

      $environmentId = $null
      if ($envResponse.data -and $envResponse.data.environment -and $envResponse.data.environment.id) {
        $environmentId = $envResponse.data.environment.id
      }
      elseif ($envResponse.environment -and $envResponse.environment.id) { $environmentId = $envResponse.environment.id }
      elseif ($envResponse.data -and $envResponse.data.id)               { $environmentId = $envResponse.data.id }
      elseif ($envResponse.id)                                           { $environmentId = $envResponse.id }
      elseif ($envResponse._id)                                          { $environmentId = $envResponse._id }

      if (-not $agentToken -or -not $environmentId) {
        Log "FAILED: Missing agent_token or environment_id"
        Log "  Response: $($envResponse | ConvertTo-Json -Compress -Depth 5)"
        exit 1
      }

      Log "  Agent token:    $($agentToken.Substring(0, [Math]::Min(20, $agentToken.Length)))..."
      Log "  Environment ID: $environmentId"

      # ── Step 5: Write to JSON file for Terraform to consume ──
      $output = @{
        agent_token    = $agentToken
        environment_id = $environmentId
      } | ConvertTo-Json

      $output | Set-Content -Path $outputFile -Force
      Log "Step 5 — Outputs written to $outputFile"
      Log "SUCCESS: Environment setup complete."
    EOT
  }
}

# =============================================================================
# Read the setup outputs (depends_on ensures file exists before reading)
# =============================================================================

data "local_file" "site24x7_env_output" {
  depends_on = [terraform_data.site24x7_env_setup]
  filename   = local.env_output_file
}

locals {
  env_output = jsondecode(data.local_file.site24x7_env_output.content)

  site24x7_token          = local.env_output.agent_token
  site24x7_environment_id = local.env_output.environment_id
  site24x7_server_address = "${var.site24x7_server}:9090"
}

# =============================================================================
# Step 2 — Kubernetes resources for the Chaos Agent
# =============================================================================

resource "kubernetes_namespace" "site24x7_labs" {
  depends_on = [terraform_data.site24x7_env_setup]

  metadata {
    name = var.site24x7_namespace
    labels = {
      "app.kubernetes.io/part-of" = "site24x7-labs"
    }
  }
}

resource "kubernetes_secret" "site24x7_agent_token" {
  depends_on = [kubernetes_namespace.site24x7_labs]

  metadata {
    name      = "site24x7-labs-agent-secret"
    namespace = var.site24x7_namespace
  }

  data = {
    AGENT_TOKEN = local.site24x7_token
  }

  type = "Opaque"
}

resource "kubernetes_service_account" "site24x7_agent" {
  depends_on = [kubernetes_namespace.site24x7_labs]

  metadata {
    name      = "site24x7-labs-agent"
    namespace = var.site24x7_namespace
    labels = {
      "app.kubernetes.io/component" = "agent"
      "app.kubernetes.io/part-of"   = "site24x7-labs"
    }
  }
}

resource "kubernetes_cluster_role" "site24x7_agent" {
  metadata {
    name = "site24x7-labs-agent"
    labels = {
      "app.kubernetes.io/component" = "agent"
      "app.kubernetes.io/part-of"   = "site24x7-labs"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch", "delete", "deletecollection"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["create"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get"]
  }
  rule {
    api_groups = [""]
    resources  = ["services", "endpoints", "nodes"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets", "daemonsets", "replicasets"]
    verbs      = ["get", "list", "watch", "update", "patch"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["networkpolicies"]
    verbs      = ["get", "list", "create", "update", "delete"]
  }
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["get", "list", "watch", "create"]
  }
}

resource "kubernetes_cluster_role_binding" "site24x7_agent" {
  metadata {
    name = "site24x7-labs-agent"
    labels = {
      "app.kubernetes.io/component" = "agent"
      "app.kubernetes.io/part-of"   = "site24x7-labs"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.site24x7_agent.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.site24x7_agent.metadata[0].name
    namespace = var.site24x7_namespace
  }
}

resource "kubernetes_daemon_set_v1" "site24x7_agent" {
  depends_on = [
    kubernetes_namespace.site24x7_labs,
    kubernetes_secret.site24x7_agent_token,
    kubernetes_service_account.site24x7_agent,
    kubernetes_cluster_role_binding.site24x7_agent,
  ]

  metadata {
    name      = "site24x7-labs-agent"
    namespace = var.site24x7_namespace
    labels = {
      "app.kubernetes.io/component" = "agent"
      "app.kubernetes.io/part-of"   = "site24x7-labs"
    }
  }

  spec {
    selector {
      match_labels = {
        "app.kubernetes.io/component" = "agent"
        "app.kubernetes.io/part-of"   = "site24x7-labs"
      }
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_unavailable = "1"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/component" = "agent"
          "app.kubernetes.io/part-of"   = "site24x7-labs"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.site24x7_agent.metadata[0].name
        host_pid             = true

        init_container {
          name    = "fix-permissions"
          image   = "busybox:1.36"
          command = ["sh", "-c", "mkdir -p /var/site24x7-labs/faults && chmod 777 /var/site24x7-labs/faults"]

          volume_mount {
            name       = "chaos-config"
            mount_path = "/var/site24x7-labs/faults"
          }

          security_context {
            run_as_user = 0
          }
        }

        container {
          name              = "agent"
          image             = var.site24x7_image
          image_pull_policy = "Always"

          env {
            name  = "SERVER_ADDRESS"
            value = local.site24x7_server_address
          }
          env {
            name = "AGENT_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.site24x7_agent_token.metadata[0].name
                key  = "AGENT_TOKEN"
              }
            }
          }
          env {
            name  = "AGENT_ENVIRONMENT"
            value = local.site24x7_environment_id
          }
          env {
            name = "AGENT_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
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
            name = "POD_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }
          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          env {
            name  = "ENABLE_KUBERNETES"
            value = "true"
          }
          env {
            name  = "ENABLE_DOCKER"
            value = "false"
          }
          env {
            name  = "ENABLE_HOST"
            value = "true"
          }
          env {
            name  = "CHAOS_CONFIG_DIR"
            value = "/var/site24x7-labs/faults"
          }
          env {
            name  = "LOG_LEVEL"
            value = "info"
          }
          env {
            name  = "LOG_FORMAT"
            value = "json"
          }

          security_context {
            privileged = true
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "proc"
            mount_path = "/host/proc"
            read_only  = true
          }
          volume_mount {
            name       = "sys"
            mount_path = "/host/sys"
            read_only  = true
          }
          volume_mount {
            name       = "cgroup"
            mount_path = "/host/cgroup"
            read_only  = true
          }
          volume_mount {
            name       = "chaos-config"
            mount_path = "/var/site24x7-labs/faults"
          }

          liveness_probe {
            exec {
              command = ["/bin/sh", "-c", "pgrep -f site24x7-labs-agent"]
            }
            initial_delay_seconds = 10
            period_seconds        = 30
            timeout_seconds       = 5
          }

          readiness_probe {
            exec {
              command = ["/bin/sh", "-c", "pgrep -f site24x7-labs-agent"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 3
          }
        }

        volume {
          name = "proc"
          host_path {
            path = "/proc"
          }
        }
        volume {
          name = "sys"
          host_path {
            path = "/sys"
          }
        }
        volume {
          name = "cgroup"
          host_path {
            path = "/sys/fs/cgroup"
          }
        }
        volume {
          name = "chaos-config"
          host_path {
            path = "/var/site24x7-labs/faults"
            type = "DirectoryOrCreate"
          }
        }

        toleration {
          operator = "Exists"
        }
      }
    }
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "site24x7_chaos_agent_status" {
  description = "Summary of the deployed Site24x7 Labs chaos agent"
  value = {
    cloud_provider = var.cloud_provider
    cluster_name   = var.cluster_name
    platform       = var.site24x7_platform
    namespace      = var.site24x7_namespace
    server         = var.site24x7_server
    environment_id = local.site24x7_environment_id
  }
}

output "site24x7_agent_token" {
  description = "Agent token (sensitive)"
  value       = local.site24x7_token
  sensitive   = true
}