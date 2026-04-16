# ─────────────────────────────────────────────────────────────────────────────
# ZylkerKart — Terraform Providers
# ─────────────────────────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# ── Azure Provider ──
# All Azure resources (aks.tf) are gated with count = var.cloud_provider == "azure" ? 1 : 0
# so no Azure API calls are ever made during an AWS deployment. However Terraform still
# configures every declared provider at init/plan time. The settings below prevent the
# provider from attempting any authentication method and avoid the network round-trip to
# login.microsoftonline.com that causes plan failures when Azure credentials are absent.
#
# IMPORTANT: When cloud_provider = "azure", set real values via ARM_* env vars:
#   ARM_SUBSCRIPTION_ID, ARM_TENANT_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET
#   (env vars override these placeholder values at runtime)
provider "azurerm" {
  features {}
  skip_provider_registration = true
}

# ── AWS Provider ──
provider "aws" {
  region = var.aws_region
}

# ── Kubernetes Provider (configured dynamically based on cloud) ──
provider "kubernetes" {
  host = var.cloud_provider == "azure" ? (
    length(azurerm_kubernetes_cluster.aks) > 0 ? azurerm_kubernetes_cluster.aks[0].kube_config[0].host : ""
    ) : (
    length(aws_eks_cluster.eks) > 0 ? aws_eks_cluster.eks[0].endpoint : ""
  )

  cluster_ca_certificate = base64decode(
    var.cloud_provider == "azure" ? (
      length(azurerm_kubernetes_cluster.aks) > 0 ? azurerm_kubernetes_cluster.aks[0].kube_config[0].cluster_ca_certificate : ""
      ) : (
      length(aws_eks_cluster.eks) > 0 ? aws_eks_cluster.eks[0].certificate_authority[0].data : ""
    )
  )

  # Azure uses client certificate auth
  client_certificate = var.cloud_provider == "azure" ? (
    length(azurerm_kubernetes_cluster.aks) > 0 ? base64decode(azurerm_kubernetes_cluster.aks[0].kube_config[0].client_certificate) : ""
  ) : null

  client_key = var.cloud_provider == "azure" ? (
    length(azurerm_kubernetes_cluster.aks) > 0 ? base64decode(azurerm_kubernetes_cluster.aks[0].kube_config[0].client_key) : ""
  ) : null

  # AWS uses exec-based auth
  dynamic "exec" {
    for_each = var.cloud_provider == "aws" ? [1] : []
    content {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.effective_cluster_name]
    }
  }
}

provider "helm" {
  kubernetes {
    host = var.cloud_provider == "azure" ? (
      length(azurerm_kubernetes_cluster.aks) > 0 ? azurerm_kubernetes_cluster.aks[0].kube_config[0].host : ""
      ) : (
      length(aws_eks_cluster.eks) > 0 ? aws_eks_cluster.eks[0].endpoint : ""
    )

    cluster_ca_certificate = base64decode(
      var.cloud_provider == "azure" ? (
        length(azurerm_kubernetes_cluster.aks) > 0 ? azurerm_kubernetes_cluster.aks[0].kube_config[0].cluster_ca_certificate : ""
        ) : (
        length(aws_eks_cluster.eks) > 0 ? aws_eks_cluster.eks[0].certificate_authority[0].data : ""
      )
    )

    client_certificate = var.cloud_provider == "azure" ? (
      length(azurerm_kubernetes_cluster.aks) > 0 ? base64decode(azurerm_kubernetes_cluster.aks[0].kube_config[0].client_certificate) : ""
    ) : null

    client_key = var.cloud_provider == "azure" ? (
      length(azurerm_kubernetes_cluster.aks) > 0 ? base64decode(azurerm_kubernetes_cluster.aks[0].kube_config[0].client_key) : ""
    ) : null

    dynamic "exec" {
      for_each = var.cloud_provider == "aws" ? [1] : []
      content {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args        = ["eks", "get-token", "--cluster-name", local.effective_cluster_name]
      }
    }
  }
}
