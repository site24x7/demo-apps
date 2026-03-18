# =============================================================================
# Site24x7 Monitor Group — groups all ZylkerKart APM applications
# Uses the Site24x7 REST API directly (the Terraform provider does not support
# the "monitors" attribute in its schema, so we call the API via PowerShell).
# Runs after the APM workflow completes (depends on apm_state_refresh).
# =============================================================================

locals {
  # Extract all application IDs from the APM workflow
  apm_application_ids = local.enable_apm ? keys(local.applications) : []

  # Monitor group display name — includes ticket suffix when set
  mg_display_name = "ZylkerKart APM${local.ticket_suffix}"

  # Comma-separated list of monitor IDs for the PowerShell script
  mg_monitor_ids_csv = join(",", local.apm_application_ids)

  # Output file for the monitor group creation result
  mg_output_file = "${abspath(path.module)}/.monitor_group_output.json"
}

# ──────────────────────────────────────────────
# Monitor Group — create/update via REST API
# ──────────────────────────────────────────────
resource "terraform_data" "zylkerkart_monitor_group" {
  count = local.enable_apm ? 1 : 0

  # Re-run only when application IDs or group name change
  triggers_replace = [
    sha256(join(",", sort(local.apm_application_ids))),
    local.mg_display_name,
  ]

  depends_on = [terraform_data.apm_state_refresh]

  input = {
    group_name  = local.mg_display_name
    monitor_ids = local.mg_monitor_ids_csv
    output_file = local.mg_output_file
  }

  provisioner "local-exec" {
    interpreter = ["powershell", "-NoProfile", "-Command"]

    command = <<-EOT
      & "${abspath(path.module)}/scripts/create_monitor_group.ps1" `
        -GroupName "${local.mg_display_name}" `
        -MonitorIds "${local.mg_monitor_ids_csv}" `
        -OutputFile "${local.mg_output_file}"
    EOT
  }
}
