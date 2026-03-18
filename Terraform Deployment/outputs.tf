# ─────────────────────────────────────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────────────────────────────────────

output "cloud_provider" {
  value = var.cloud_provider
}

output "cluster_name" {
  value = var.cluster_name
}

# ── Azure AKS Outputs ──
output "aks_kube_config" {
  value     = var.cloud_provider == "azure" && length(azurerm_kubernetes_cluster.aks) > 0 ? azurerm_kubernetes_cluster.aks[0].kube_config_raw : null
  sensitive = true
}

output "aks_cluster_fqdn" {
  value = var.cloud_provider == "azure" && length(azurerm_kubernetes_cluster.aks) > 0 ? azurerm_kubernetes_cluster.aks[0].fqdn : null
}

output "storefront_external_ip" {
  description = "External IP or hostname of the Storefront LoadBalancer service"
  value = try(
    kubernetes_service.storefront.status[0].load_balancer[0].ingress[0].ip,
    kubernetes_service.storefront.status[0].load_balancer[0].ingress[0].hostname,
    "pending"
  )
}

# ── AWS EKS Outputs ──
output "eks_cluster_endpoint" {
  value = var.cloud_provider == "aws" && length(aws_eks_cluster.eks) > 0 ? aws_eks_cluster.eks[0].endpoint : null
}

output "eks_cluster_ca_certificate" {
  value     = var.cloud_provider == "aws" && length(aws_eks_cluster.eks) > 0 ? aws_eks_cluster.eks[0].certificate_authority[0].data : null
  sensitive = true
}

output "eks_kubeconfig_command" {
  value = var.cloud_provider == "aws" ? "aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}" : null
}


output "apm_enabled" {
  value     = local.enable_apm
  sensitive = true
}

output "filter_prefix" {
  description = "Only managing APM apps with this name prefix"
  value       = local.enable_apm ? var.apm_app_name_prefix : null
  sensitive   = true

}

output "managed_applications" {
  description = "APM applications matching the filter (refreshed on apply, deleted from Site24x7 only on destroy)"
  sensitive   = true
  value = local.enable_apm ? {
    for app_id, app in local.applications :
    app_id => app.application_name
  } : {}
}

output "skipped_applications" {
  description = "APM applications NOT matching the filter (will NOT be deleted)"
  value       = local.enable_apm ? local.skipped_applications : {}
  sensitive   = true

}

output "application_summary" {
  description = "Summary of managed APM applications"
  sensitive   = true

  value = local.enable_apm ? {
    for app_id, app in local.applications :
    app_id => {
      name           = app.application_name
      instance_count = app.instance_count
      availability   = app.availability
      apdex          = app.apdex
      response_time  = app.response_time
      throughput     = app.throughput
      error_count    = app.error_count
    }
  } : {}

}

output "all_instances" {
  description = "All instances of managed APM applications"
  value       = local.enable_apm ? local.all_instances : []
  sensitive   = true

}

output "total_managed_apps" {
  value     = local.enable_apm ? length(local.applications) : 0
  sensitive = true

}

output "total_managed_instances" {
  value     = local.enable_apm ? length(local.all_instances) : 0
  sensitive = true

}

output "total_skipped_apps" {
  value     = local.enable_apm ? length(local.skipped_applications) : 0
  sensitive = true

}