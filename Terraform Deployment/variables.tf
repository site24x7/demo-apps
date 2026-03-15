# ─────────────────────────────────────────────────────────────────────────────
# ZylkerKart — Terraform Variables
# ─────────────────────────────────────────────────────────────────────────────

variable "cloud_provider" {
  description = "Which cloud to deploy: 'azure' or 'aws'"
  type        = string
  validation {
    condition     = contains(["azure", "aws"], var.cloud_provider)
    error_message = "cloud_provider must be 'azure' or 'aws'."
  }
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "zylkerkart-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

# ── Azure-specific ──
variable "azure_resource_group_name" {
  description = "Azure Resource Group name"
  type        = string
  default     = "rg-zylkerkart"
}

variable "azure_location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

# ── AWS-specific ──
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_vpc_cidr" {
  description = "VPC CIDR block for EKS"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aws_subnet_cidrs" {
  description = "Subnet CIDR blocks for EKS (need at least 2 AZs)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

# ── ZylkerKart App Config ──
variable "docker_registry" {
  description = "Docker registry prefix for ZylkerKart images"
  type        = string
  default     = "zylkerkart"
}

variable "image_tag" {
  description = "Docker image tag"
  type        = string
  default     = "latest"
}

variable "site24x7_license_key" {
  description = "Site24x7 APM license key (leave empty to skip APM)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "mysql_root_password" {
  description = "MySQL root password"
  type        = string
  default     = "ZylkerKart@2024"
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT signing secret (min 32 chars)"
  type        = string
  default     = "ZylkerKart-Super-Secret-JWT-Key-2024-Must-Be-At-Least-32-Chars"
  sensitive   = true
}

# ── Computed locals ──
locals {
  enable_apm    = var.site24x7_license_key != ""
  node_size     = var.cloud_provider == "azure" ? "Standard_D4s_v3" : "t3.xlarge"
  storage_class = var.cloud_provider == "azure" ? "default" : "gp2"
}

variable "apm_app_name_prefix" {
  description = "Only manage APM monitors whose name starts with this prefix"
  type        = string
  default     = "ZylkerKart-"
}

variable "expected_app_count" {
  description = "Number of APM applications expected to register before proceeding"
  type        = number
  default     = 6
}