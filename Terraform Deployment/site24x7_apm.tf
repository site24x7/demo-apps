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
      $response = Invoke-RestMethod -Uri 'https://accounts.zoho.com/oauth/v2/token' -Method POST -Body $body
      @{ access_token = $response.access_token } | ConvertTo-Json -Compress
    EOT
  ]
  depends_on = [terraform_data.k8s_ready]
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
        -DelaySec 30
    EOT
  }

  depends_on = [terraform_data.k8s_ready]
}

# ──────────────────────────────────────────────
# 3. Fetch APM Applications
# ──────────────────────────────────────────────
data "http" "apm_apps" {
  count = local.enable_apm ? 1 : 0

  url = "https://www.site24x7.com/api/apminsight/app/H"

  request_headers = {
    Accept        = "application/json; version=2.0"
    Authorization = "Zoho-oauthtoken ${data.external.site24x7_token[0].result["access_token"]}"
  }
  depends_on = [null_resource.wait_for_apm_agents]
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
}

# ──────────────────────────────────────────────
# 5a. REFRESH state file on every apply
# ──────────────────────────────────────────────
resource "terraform_data" "apm_state_refresh" {
  count = local.enable_apm ? 1 : 0

  triggers_replace = [timestamp()]

  input = {
    state_file = "${abspath(path.module)}/apm_monitors_state.json"
    script_dir = "${abspath(path.module)}/scripts"
    app_prefix = var.apm_app_name_prefix
  }

  provisioner "local-exec" {
    interpreter = ["powershell", "-NoProfile", "-Command"]

    command = <<-EOT
      & "${abspath(path.module)}/scripts/fetch_and_store_apm.ps1" `
        -OutputFile "${abspath(path.module)}/apm_monitors_state.json" `
        -AppNamePrefix "${var.apm_app_name_prefix}" `
        -ExpectedAppCount ${var.expected_app_count}
    EOT
  }
}

# ──────────────────────────────────────────────
# 5b. DELETE APM monitors only on terraform destroy
# ──────────────────────────────────────────────
resource "terraform_data" "apm_monitor_cleanup" {
  count = local.enable_apm ? 1 : 0

  input = {
    state_file = "${abspath(path.module)}/apm_monitors_state.json"
    script_dir = "${abspath(path.module)}/scripts"
    app_prefix = var.apm_app_name_prefix
  }

  depends_on = [terraform_data.apm_state_refresh]

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["powershell", "-NoProfile", "-Command"]

    command = <<-EOT
      & "${self.input.script_dir}/delete_apm_monitors.ps1" `
        -InputFile "${self.input.state_file}" `
        -AppNamePrefix "${self.input.app_prefix}"
    EOT
  }
}