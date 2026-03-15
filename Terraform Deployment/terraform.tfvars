# ─────────────────────────────────────────────────────────────────────────────
# Example — Deploy to Azure AKS
# ─────────────────────────────────────────────────────────────────────────────
cloud_provider = "azure" # or "aws"
cluster_name   = "zylkerkart-cluster"

# Azure
azure_resource_group_name = "rg-zylkerkart"
azure_location            = "westus"

# AWS (used when cloud_provider = "aws")
# aws_region = "us-east-1"

# Cluster
kubernetes_version = "1.33"
node_count         = 3

# App
docker_registry      = "impazhani"
image_tag            = "chaos"
site24x7_license_key = "" # Set to enable APM
mysql_root_password  = "ZylkerKart@2024"
jwt_secret           = "ZylkerKart-Super-Secret-JWT-Key-2024-Must-Be-At-Least-32-Chars"

