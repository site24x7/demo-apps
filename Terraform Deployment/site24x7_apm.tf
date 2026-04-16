# ──────────────────────────────────────────────
# 1. Refresh OAuth Token
# ──────────────────────────────────────────────
data "external" "site24x7_token" {
  count = local.enable_apm ? 1 : 0

  program = [
    "powershell",
    "-NoProfile",
    "-Command",
    <<-EOT
      $body = @{
        grant_type    = 'refresh_token'
        client_id     = $env:SITE24X7_CLIENT_ID
        client_secret = $env:SITE24X7_CLIENT_SECRET
        refresh_token = $env:SITE24X7_REFRESH_TOKEN
      }
      $response = Invoke-RestMethod -Uri '${local.zoho_accounts_base}/oauth/v2/token' -Method POST -Body $body
      @{ access_token = $response.access_token } | ConvertTo-Json -Compress
    EOT
  ]
  depends_on = [
    terraform_data.k8s_ready,
    kubernetes_daemon_set_v1.site24x7_agent,
  ]
}

# ──────────────────────────────────────────────
# 2. Wait for ALL APM agents to register
#    Polls every 30s, up to ~3.5 minutes (7 attempts)
# ──────────────────────────────────────────────
resource "null_resource" "wait_for_apm_agents" {
  count = local.enable_apm ? 1 : 0

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["powershell", "-NoProfile", "-Command"]

    command = <<-EOT
      & "${abspath(path.module)}/scripts/wait_for_apm_registration.ps1" `
        -AppNamePrefix "${var.apm_app_name_prefix}" `
        -ExpectedAppCount ${var.expected_app_count} `
        -MaxAttempts 7 `
        -DelaySec 30 `
        -ZohoAccountsBase "${local.zoho_accounts_base}" `
        -Site24x7ApiBase "${local.site24x7_api_base}"
    EOT
  }

  depends_on = [
    terraform_data.k8s_ready,
    kubernetes_daemon_set_v1.site24x7_agent,
  ]
}

# ──────────────────────────────────────────────
# 3. Fetch APM Applications
# ──────────────────────────────────────────────
data "http" "apm_apps" {
  count = local.enable_apm ? 1 : 0

  url = "${local.site24x7_api_base}/api/apminsight/app/H"

  request_headers = {
    Accept        = "application/json; version=2.0"
    Authorization = "Zoho-oauthtoken ${data.external.site24x7_token[0].result["access_token"]}"
  }
  depends_on = [
    null_resource.wait_for_apm_agents,
    terraform_data.k8s_ready,
  ]

}

# ──────────────────────────────────────────────
# 3b. Fetch Kubernetes Cluster Monitors
# ──────────────────────────────────────────────
data "http" "k8s_monitors" {
  count = local.enable_apm ? 1 : 0

  url = "${local.site24x7_api_base}/app/api/server/dashboard/kubernetes?show_child=false"

  request_headers = {
    Accept        = "application/json; version=2.0"
    Authorization = "Zoho-oauthtoken ${data.external.site24x7_token[0].result["access_token"]}"
  }
  depends_on = [
    null_resource.wait_for_apm_agents,
    terraform_data.k8s_ready,
  ]
}

# ──────────────────────────────────────────────
# 4. Parse — only apps matching the prefix
# ──────────────────────────────────────────────
locals {
  apm_apps_raw = local.enable_apm ? jsondecode(data.http.apm_apps[0].response_body) : null
  apm_app_list = try(local.apm_apps_raw.data, [])

  applications = {
    for app in local.apm_app_list :
    app.application_info.application_id => {
      application_id   = app.application_info.application_id
      application_name = app.application_info.application_name
      instance_ids     = app.application_info.instance_ids
      host_count       = app.application_info.host_count
      instance_count   = app.application_info.instance_count
      hosts            = app.application_info.hosts
      is_cloud_app     = try(app.app_config.is_cloud_app, false)

      response_time     = try(app.response_time_data.response_time, 0)
      max_response_time = try(app.response_time_data.max_response_time, 0)
      throughput        = try(app.response_time_data.throughput, 0)
      error_count       = try(app.response_time_data.error_count, 0)
      request_count     = try(app.response_time_data.request_count, 0)
      warning_count     = try(app.exception_info.warning_count, "0")
      fatal_count       = try(app.exception_info.fatal_count, "0")

      availability = app.availability_health_info.availability
      apdex        = try(app.apdex_data.apdex, 0)

      instances = {
        for inst_id, inst in app.application_info.instances :
        inst_id => {
          instance_id        = inst.instance_id
          instance_name      = inst.instance_name
          host               = inst.host
          port               = inst.port
          ip_address         = try(inst.ip_address, "")
          ins_type           = inst.ins_type
          agent_version      = inst.agent_version
          agent_version_info = try(inst.agent_version_info, "")
          cloud_type         = try(inst.cloud_type, "")
          is_cloud_ins       = try(inst.is_cloud_ins, false)
        }
      }
    }
    if startswith(app.application_info.application_name, var.apm_app_name_prefix)
  }

  skipped_applications = {
    for app in local.apm_app_list :
    app.application_info.application_id => app.application_info.application_name
    if !startswith(app.application_info.application_name, var.apm_app_name_prefix)
  }

  all_instances = flatten([
    for app_id, app in local.applications : [
      for inst_id, inst in app.instances : {
        application_id   = app.application_id
        application_name = app.application_name
        instance_id      = inst.instance_id
        instance_name    = inst.instance_name
        host             = inst.host
        port             = inst.port
        ip_address       = inst.ip_address
        ins_type         = inst.ins_type
        agent_version    = inst.agent_version
        cloud_type       = inst.cloud_type
        availability     = app.availability
        response_time    = app.response_time
        apdex            = app.apdex
      }
    ]
  ])

  # ── Kubernetes Cluster Monitors ──
  k8s_raw  = local.enable_apm ? jsondecode(data.http.k8s_monitors[0].response_body) : null
  k8s_list = try(local.k8s_raw.data, [])

  # Filter K8s monitors by effective cluster name
  k8s_clusters = {
    for cluster in local.k8s_list :
    try(cluster.cluster_id, cluster.monitor_id, cluster.resource_id, "") => {
      cluster_id   = try(cluster.cluster_id, cluster.monitor_id, cluster.resource_id, "")
      display_name = try(cluster.display_name, cluster.name, cluster.cluster_name, "")
    }
    if contains(
      lower(try(cluster.display_name, cluster.name, cluster.cluster_name, "")),
      lower(local.effective_cluster_name)
    )
  }

  k8s_skipped_clusters = {
    for cluster in local.k8s_list :
    try(cluster.cluster_id, cluster.monitor_id, cluster.resource_id, "") =>
    try(cluster.display_name, cluster.name, cluster.cluster_name, "")
    if !contains(
      lower(try(cluster.display_name, cluster.name, cluster.cluster_name, "")),
      lower(local.effective_cluster_name)
    )
  }
}

# ──────────────────────────────────────────────
# 5a. REFRESH state file on every apply
# ──────────────────────────────────────────────
resource "terraform_data" "apm_state_refresh" {
  count = local.enable_apm ? 1 : 0

  triggers_replace = [timestamp()]

  depends_on = [data.http.apm_apps, data.http.k8s_monitors]

  input = {
    state_file         = "${abspath(path.module)}/apm_monitors_state.json"
    script_dir         = "${abspath(path.module)}/scripts"
    app_prefix         = var.apm_app_name_prefix
    cluster_name       = local.effective_cluster_name
    zoho_accounts_base = local.zoho_accounts_base
    site24x7_api_base  = local.site24x7_api_base
  }

  provisioner "local-exec" {
    interpreter = ["powershell", "-NoProfile", "-Command"]

    command = <<-EOT
      & "${abspath(path.module)}/scripts/fetch_and_store_apm.ps1" `
        -OutputFile "${abspath(path.module)}/apm_monitors_state.json" `
        -AppNamePrefix "${var.apm_app_name_prefix}" `
        -ExpectedAppCount ${var.expected_app_count} `
        -ClusterName "${local.effective_cluster_name}" `
        -ZohoAccountsBase "${local.zoho_accounts_base}" `
        -Site24x7ApiBase "${local.site24x7_api_base}"
    EOT
  }
}

# ──────────────────────────────────────────────
# 5b. DELETE APM monitors only on terraform destroy
# ──────────────────────────────────────────────
resource "terraform_data" "apm_monitor_cleanup" {
  count = local.enable_apm ? 1 : 0

  input = {
    state_file         = "${abspath(path.module)}/apm_monitors_state.json"
    script_dir         = "${abspath(path.module)}/scripts"
    app_prefix         = var.apm_app_name_prefix
    cluster_name       = local.effective_cluster_name
    zoho_accounts_base = local.zoho_accounts_base
    site24x7_api_base  = local.site24x7_api_base
  }

  depends_on = [
    terraform_data.apm_state_refresh,
    # Destroy ordering: APM cleanup destroys before chaos agent K8s resources
    kubernetes_daemon_set_v1.site24x7_agent,
  ]

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["powershell", "-NoProfile", "-Command"]

    command = <<-EOT
      & "${self.input.script_dir}/delete_apm_monitors.ps1" `
        -InputFile "${self.input.state_file}" `
        -AppNamePrefix "${self.input.app_prefix}" `
        -ClusterName "${self.input.cluster_name}"
    EOT
  }
}

# =============================================================================
# 6. Site24x7 Dashboard — auto-generated from discovered APM & K8s monitors
# =============================================================================

locals {
  # Dashboard display name — includes ticket suffix when set
  dashboard_display_name = "ZylkerKart Operations${local.ticket_suffix}"

  # Output file for the dashboard creation result (used by destroy provisioner)
  dashboard_output_file = "${abspath(path.module)}/.dashboard_output.json"

  # Widgets JSON file written by Terraform and consumed by the PowerShell script
  dashboard_widgets_file = "${abspath(path.module)}/.dashboard_widgets.json"

  # ── Sorted application IDs for deterministic widget layout ──
  sorted_app_ids = sort(keys(local.applications))

  # ── Widget: Overall status of all APM monitors ──
  widget_all_monitors_status = {
    name                = "Current Status - All ZylkerKart Monitors"
    widget_reference_id = 10000
    config_data = {
      version = "0.2"
      grid_details = {
        x           = 0
        y           = 0
        cols        = 80
        rows        = 20
        minItemCols = 7
        minItemRows = 7
        version     = "2.1"
      }
      params = {
        selection_type  = 2
        resource_ids    = local.sorted_app_ids
        status_required = ["0", "1", "2", "3", "5", "7", "9", "10"]
      }
    }
  }

  # ── Widget: Availability chart for all APM applications ──
  widget_availability_chart = {
    name                = "Availability - ZylkerKart APM Applications"
    widget_reference_id = 100001
    config_data = {
      version = "0.1"
      grid_details = {
        x           = 0
        y           = 20
        cols        = 40
        rows        = 15
        minItemCols = 7
        minItemRows = 7
        version     = "2.1"
      }
      params = {
        selection_type = 2
        period         = 0
        resource_ids   = local.sorted_app_ids
      }
    }
  }

  # ── Widget: Response time chart for all APM applications ──
  widget_response_time_chart = {
    name                = "Response Time - ZylkerKart APM Applications"
    widget_reference_id = 100002
    config_data = {
      version = "0.1"
      chart_data = {
        custom_chart_info = {
          chart_type = "TimeChart"
        }
      }
      grid_details = {
        x           = 40
        y           = 20
        cols        = 40
        rows        = 15
        minItemCols = 7
        minItemRows = 7
        version     = "2.1"
      }
      params = {
        selection_type = 2
        period         = 0
        resource_ids   = local.sorted_app_ids
      }
    }
  }

  # ── Per-application Apdex score widgets (one per APM app, laid out in a row) ──
  widget_per_app_apdex = [
    for idx, app_id in local.sorted_app_ids : {
      name                = "Apdex - ${local.applications[app_id].application_name}"
      widget_reference_id = 100013
      config_data = {
        version   = "0.2"
        font_size = "48"
        grid_details = {
          x           = (idx % 4) * 20
          y           = 35 + (floor(idx / 4) * 15)
          cols        = 20
          rows        = 15
          minItemCols = 7
          minItemRows = 7
          version     = "2.1"
        }
        params = {
          selection_type = 2
          period         = 0
          resource_ids   = [app_id]
          thresholds = [
            { condition = 3, color = "#2ecc71", value = 0.9 },
            { condition = 3, color = "#f7c228", value = 0.5 },
            { condition = 2, color = "#e74c3c", value = 0.5 },
          ]
        }
      }
    }
  ]

  # ── Per-application current status widgets (below the Apdex row) ──
  apdex_rows_needed = ceil(length(local.sorted_app_ids) / 4)
  per_app_y_start   = 35 + (local.apdex_rows_needed * 15)

  widget_per_app_status = [
    for idx, app_id in local.sorted_app_ids : {
      name                = "Status - ${local.applications[app_id].application_name}"
      widget_reference_id = 10000
      config_data = {
        version = "0.2"
        grid_details = {
          x           = (idx % 4) * 20
          y           = local.per_app_y_start + (floor(idx / 4) * 10)
          cols        = 20
          rows        = 10
          minItemCols = 7
          minItemRows = 7
          version     = "2.1"
        }
        params = {
          selection_type  = 2
          resource_ids    = [app_id]
          status_required = ["0", "1", "2", "3", "5", "7", "9", "10"]
        }
      }
    }
  ]

  # ── K8s cluster status widget (if cluster monitors found) ──
  k8s_cluster_ids    = keys(local.k8s_clusters)
  status_rows_needed = ceil(length(local.sorted_app_ids) / 4)
  k8s_y_start        = local.per_app_y_start + (local.status_rows_needed * 10)

  widget_k8s_cluster = length(local.k8s_cluster_ids) > 0 ? [{
    name                = "Kubernetes Cluster - ${var.cluster_name}"
    widget_reference_id = 10000
    config_data = {
      version = "0.2"
      grid_details = {
        x           = 0
        y           = local.k8s_y_start
        cols        = 80
        rows        = 15
        minItemCols = 7
        minItemRows = 7
        version     = "2.1"
      }
      params = {
        selection_type  = 2
        resource_ids    = local.k8s_cluster_ids
        status_required = ["0", "1", "2", "3", "5", "7", "9", "10"]
      }
    }
  }] : []

  # ── Assemble all widgets ──
  # NOTE: Site24x7 API expects config_data as a JSON *string*, not a nested object.
  # We jsonencode each widget's config_data so the final payload sends it correctly.
  _raw_dashboard_widgets = concat(
    [local.widget_all_monitors_status],
    [local.widget_availability_chart],
    [local.widget_response_time_chart],
    local.widget_per_app_apdex,
    local.widget_per_app_status,
    local.widget_k8s_cluster,
  )

  dashboard_widgets = [
    for w in local._raw_dashboard_widgets : {
      name                = w.name
      widget_reference_id = w.widget_reference_id
      config_data         = jsonencode(w.config_data)
    }
  ]
}

# ──────────────────────────────────────────────
# 6a. Write the widgets JSON file for the script
# ──────────────────────────────────────────────
resource "local_file" "dashboard_widgets" {
  count = local.enable_apm ? 1 : 0

  filename = local.dashboard_widgets_file
  content  = jsonencode(local.dashboard_widgets)

  depends_on = [terraform_data.apm_state_refresh]
}

# ──────────────────────────────────────────────
# 6b. CREATE / UPDATE the dashboard via REST API
# ──────────────────────────────────────────────
resource "terraform_data" "zylkerkart_dashboard" {
  count = local.enable_apm ? 1 : 0

  triggers_replace = [
    sha256(jsonencode(local.dashboard_widgets)),
    local.dashboard_display_name,
    var.site24x7_dashboard_theme,
  ]

  depends_on = [
    terraform_data.apm_state_refresh,
    local_file.dashboard_widgets,
    terraform_data.zylkerkart_monitor_group,
  ]

  input = {
    dashboard_name     = local.dashboard_display_name
    output_file        = local.dashboard_output_file
    widgets_file       = local.dashboard_widgets_file
    script_dir         = "${abspath(path.module)}/scripts"
    theme              = var.site24x7_dashboard_theme
    zoho_accounts_base = local.zoho_accounts_base
    site24x7_api_base  = local.site24x7_api_base
  }

  provisioner "local-exec" {
    interpreter = ["powershell", "-NoProfile", "-Command"]

    command = <<-EOT
      & "${abspath(path.module)}/scripts/create_dashboard.ps1" `
        -DashboardName "${local.dashboard_display_name}" `
        -Theme ${var.site24x7_dashboard_theme} `
        -Size 10 `
        -Version "2.1" `
        -Description "Auto-generated ZylkerKart operations dashboard" `
        -WidgetsFile "${local.dashboard_widgets_file}" `
        -OutputFile "${local.dashboard_output_file}" `
        -ZohoAccountsBase "${local.zoho_accounts_base}" `
        -Site24x7ApiBase "${local.site24x7_api_base}"
    EOT
  }

  # Delete on destroy
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["powershell", "-NoProfile", "-Command"]

    command = <<-EOT
      & "${self.input.script_dir}/delete_dashboard.ps1" `
        -OutputFile "${self.input.output_file}"
    EOT
  }
}