# ─────────────────────────────────────────────────────────────────────────────
# Azure AKS Cluster
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "aks" {
  count    = var.cloud_provider == "azure" ? 1 : 0
  name     = var.azure_resource_group_name
  location = var.azure_location

  tags = {
    project     = "zylkerkart"
    environment = "production"
  }

  lifecycle {
    ignore_changes = all
  }
}

resource "azurerm_kubernetes_cluster" "aks" {
  count               = var.cloud_provider == "azure" ? 1 : 0
  name                = var.cluster_name
  location            = azurerm_resource_group.aks[0].location
  resource_group_name = azurerm_resource_group.aks[0].name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                = "default"
    vm_size             = local.node_size
    enable_auto_scaling = true
    min_count           = 2
    max_count           = 5

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  tags = {
    project     = "zylkerkart"
    environment = "production"
  }

  lifecycle {
    ignore_changes = all
  }
}