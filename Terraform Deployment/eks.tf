# ─────────────────────────────────────────────────────────────────────────────
# AWS EKS Cluster
# ─────────────────────────────────────────────────────────────────────────────

# ── VPC ──
resource "aws_vpc" "eks" {
  count                = var.cloud_provider == "aws" ? 1 : 0
  cidr_block           = var.aws_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "${var.cluster_name}-vpc"
    project = "zylkerkart"
  }
}

data "aws_availability_zones" "available" {
  count = var.cloud_provider == "aws" ? 1 : 0
  state = "available"
}

resource "aws_subnet" "eks" {
  count                   = var.cloud_provider == "aws" ? length(var.aws_subnet_cidrs) : 0
  vpc_id                  = aws_vpc.eks[0].id
  cidr_block              = var.aws_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available[0].names[count.index % length(data.aws_availability_zones.available[0].names)]
  map_public_ip_on_launch = true

  tags = {
    Name                                                    = "${var.cluster_name}-subnet-${count.index}"
    "kubernetes.io/cluster/${local.effective_cluster_name}" = "shared"
    "kubernetes.io/role/elb"                                = "1"
  }

  # Ensures terraform_data.aws_lb_cleanup's destroy provisioner runs (and all
  # cluster-tagged NLBs are fully deleted) BEFORE Terraform attempts to delete
  # these subnets.  Without this, leftover load-balancer ENIs cause:
  #   DependencyViolation: The subnet '...' has dependencies and cannot be deleted
  depends_on = [terraform_data.aws_lb_cleanup]
}

resource "aws_internet_gateway" "eks" {
  count  = var.cloud_provider == "aws" ? 1 : 0
  vpc_id = aws_vpc.eks[0].id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_route_table" "eks" {
  count  = var.cloud_provider == "aws" ? 1 : 0
  vpc_id = aws_vpc.eks[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks[0].id
  }

  tags = {
    Name = "${var.cluster_name}-rt"
  }
}

resource "aws_route_table_association" "eks" {
  count          = var.cloud_provider == "aws" ? length(var.aws_subnet_cidrs) : 0
  subnet_id      = aws_subnet.eks[count.index].id
  route_table_id = aws_route_table.eks[0].id
}

# ── IAM Role for EKS Cluster ──
resource "aws_iam_role" "eks_cluster" {
  count = var.cloud_provider == "aws" ? 1 : 0
  name  = "${local.effective_cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = {
    project = "zylkerkart"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  count      = var.cloud_provider == "aws" ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster[0].name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  count      = var.cloud_provider == "aws" ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster[0].name
}

# ── EKS Cluster ──
resource "aws_eks_cluster" "eks" {
  count    = var.cloud_provider == "aws" ? 1 : 0
  name     = local.effective_cluster_name
  role_arn = aws_iam_role.eks_cluster[0].arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = aws_subnet.eks[*].id
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
    aws_internet_gateway.eks,
    aws_route_table_association.eks,
  ]

  tags = {
    project     = "zylkerkart"
    environment = "production"
  }
}

# ── IAM Role for Node Group ──
resource "aws_iam_role" "eks_nodes" {
  count = var.cloud_provider == "aws" ? 1 : 0
  name  = "${local.effective_cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  count      = var.cloud_provider == "aws" ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes[0].name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  count      = var.cloud_provider == "aws" ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes[0].name
}

resource "aws_iam_role_policy_attachment" "eks_ecr_read" {
  count      = var.cloud_provider == "aws" ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes[0].name
}

# ── EKS Node Group ──
resource "aws_eks_node_group" "default" {
  count           = var.cloud_provider == "aws" ? 1 : 0
  cluster_name    = aws_eks_cluster.eks[0].name
  node_group_name = "${local.effective_cluster_name}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes[0].arn
  subnet_ids      = aws_subnet.eks[*].id
  instance_types  = [local.node_size]
  disk_size       = 100

  scaling_config {
    desired_size = var.node_count
    max_size     = 3
    min_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_read,
    aws_route_table_association.eks,
  ]

  tags = {
    project     = "zylkerkart"
    environment = "production"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# OIDC Provider — required for IAM Roles for Service Accounts (IRSA)
# ─────────────────────────────────────────────────────────────────────────────

data "tls_certificate" "eks" {
  count = var.cloud_provider == "aws" ? 1 : 0
  url   = aws_eks_cluster.eks[0].identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  count           = var.cloud_provider == "aws" ? 1 : 0
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks[0].identity[0].oidc[0].issuer

  tags = {
    project = "zylkerkart"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# EBS CSI Driver — required for PersistentVolume provisioning on EKS
# ─────────────────────────────────────────────────────────────────────────────

# ── IAM Role for EBS CSI Driver (with OIDC trust) ──
resource "aws_iam_role" "ebs_csi" {
  count = var.cloud_provider == "aws" ? 1 : 0
  name  = "${local.effective_cluster_name}-ebs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks[0].arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.eks[0].identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          "${replace(aws_eks_cluster.eks[0].identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }]
  })

  tags = {
    project = "zylkerkart"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count      = var.cloud_provider == "aws" ? 1 : 0
  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ─────────────────────────────────────────────────────────────────────────────
# AWS Load Balancer Cleanup — destroy-time safety net
# ─────────────────────────────────────────────────────────────────────────────
#
# PROBLEM: Kubernetes services of type LoadBalancer (storefront NLB) and the
# NGINX Ingress Controller service (ingress-nginx NLB) cause AWS to provision
# real Network Load Balancers inside the VPC subnets.  When Terraform destroys
# those Kubernetes resources the AWS Cloud Controller Manager is supposed to
# de-provision the NLBs, but it is often killed (when the node group is torn
# down) before it can finish.  The leftover NLBs hold ENIs inside the subnets,
# causing:
#   DependencyViolation: The subnet '...' has dependencies and cannot be deleted
#
# SOLUTION: A destroy-time local-exec provisioner that uses the AWS CLI to find
# every NLB / ALB / Classic-ELB tagged with this cluster and deletes them
# directly, then waits for their ENIs to be released — all BEFORE Terraform
# attempts to delete the subnets.
#
# DEPENDENCY ORDERING (no cycles):
#   aws_iam_role.eks_cluster is referenced by aws_eks_cluster (role_arn), so
#   at destroy time Terraform destroys: k8s resources → node_group → cluster
#   → iam_policy_attachments → iam_role → [THIS RESOURCE] → aws_subnet.eks
#
#   Because aws_iam_role.eks_cluster itself has NO path back to aws_subnet.eks
#   in the dependency graph, adding this resource between the IAM role and the
#   subnets does not create a cycle.  By contrast, depending directly on
#   aws_eks_cluster or aws_eks_node_group would create a cycle because both
#   transitively reference the subnets.
# ─────────────────────────────────────────────────────────────────────────────
resource "terraform_data" "aws_lb_cleanup" {
  count = var.cloud_provider == "aws" ? 1 : 0

  # Store values using only input variables / locals so that no implicit
  # resource-attribute dependency is added (which would risk a cycle).
  input = {
    cluster_name = local.effective_cluster_name
    aws_region   = var.aws_region
  }

  # Destroyed AFTER aws_iam_role.eks_cluster, which itself is destroyed after
  # the EKS cluster → all Kubernetes resources are already gone at this point,
  # so no Cloud Controller Manager can re-create the load balancers.
  depends_on = [aws_iam_role.eks_cluster]

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["powershell", "-NoProfile", "-Command"]
    command     = <<-EOT
      $clusterName = "${self.input.cluster_name}"
      $region      = "${self.input.aws_region}"

      Write-Host "=== AWS LB cleanup for cluster '$clusterName' in $region ==="

      # ── ELBv2 (NLB / ALB) ──────────────────────────────────────────────────
      $lbsRaw = aws elbv2 describe-load-balancers --region $region --output json 2>$null
      $toDelete = @()
      if ($lbsRaw) {
        $lbs = ($lbsRaw | ConvertFrom-Json).LoadBalancers
        foreach ($lb in $lbs) {
          $tagsRaw = aws elbv2 describe-tags --region $region --resource-arns $lb.LoadBalancerArn --output json 2>$null
          if ($tagsRaw) {
            $tags = ($tagsRaw | ConvertFrom-Json).TagDescriptions[0].Tags
            $match = $tags | Where-Object { $_.Key -eq "kubernetes.io/cluster/$clusterName" }
            if ($match) {
              Write-Host "Found ELBv2: $($lb.LoadBalancerName)  [$($lb.LoadBalancerArn)]"
              $toDelete += $lb.LoadBalancerArn
            }
          }
        }
        foreach ($arn in $toDelete) {
          Write-Host "Deleting ELBv2: $arn"
          aws elbv2 delete-load-balancer --region $region --load-balancer-arn $arn 2>&1
        }
        if ($toDelete.Count -gt 0) {
          Write-Host "Waiting for ELBv2 deletion to complete..."
          $timeout = 300; $elapsed = 0
          while ($elapsed -lt $timeout) {
            $remaining = 0
            foreach ($arn in $toDelete) {
              $check = aws elbv2 describe-load-balancers --region $region --load-balancer-arns $arn --output json 2>$null
              if ($check) {
                $lbState = ($check | ConvertFrom-Json).LoadBalancers
                if ($lbState.Count -gt 0) { $remaining++ }
              }
            }
            if ($remaining -eq 0) { Write-Host "All ELBv2 load balancers deleted."; break }
            Write-Host "$remaining ELBv2 LB(s) still deleting... ($elapsed s elapsed)"
            Start-Sleep -Seconds 15; $elapsed += 15
          }
          if ($elapsed -ge $timeout) {
            Write-Host "WARNING: timed out waiting for ELBv2 deletion. Proceeding anyway."
          }
        } else {
          Write-Host "No ELBv2 load balancers found for cluster '$clusterName'."
        }
      }

      # ── Classic ELB ─────────────────────────────────────────────────────────
      $clbRaw = aws elb describe-load-balancers --region $region --output json 2>$null
      if ($clbRaw) {
        $clbs = ($clbRaw | ConvertFrom-Json).LoadBalancerDescriptions
        foreach ($clb in $clbs) {
          $tagsRaw = aws elb describe-tags --region $region --load-balancer-names $clb.LoadBalancerName --output json 2>$null
          if ($tagsRaw) {
            $tags = ($tagsRaw | ConvertFrom-Json).TagDescriptions[0].Tags
            $match = $tags | Where-Object { $_.Key -eq "kubernetes.io/cluster/$clusterName" }
            if ($match) {
              Write-Host "Deleting classic ELB: $($clb.LoadBalancerName)"
              aws elb delete-load-balancer --region $region --load-balancer-name $clb.LoadBalancerName 2>&1
            }
          }
        }
      }

      # Give ENIs time to be fully released back to the VPC before subnets
      # are deleted.  NLB ENIs typically detach within 30–60 seconds.
      Write-Host "Waiting 60s for load-balancer ENIs to be released..."
      Start-Sleep -Seconds 60
      Write-Host "Load balancer cleanup complete."
    EOT
  }
}

# ── EBS CSI Driver Addon ──
resource "aws_eks_addon" "ebs_csi" {
  count                    = var.cloud_provider == "aws" ? 1 : 0
  cluster_name             = aws_eks_cluster.eks[0].name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi[0].arn

  depends_on = [
    aws_eks_node_group.default,
    aws_iam_role_policy_attachment.ebs_csi,
    aws_iam_openid_connect_provider.eks,
    # NOTE: destroy-ordering against the PVC cleanup is handled by
    # terraform_data.mysql_pvc_finalizer_cleanup depending on THIS resource,
    # not the other way around. That direction avoids a create-time deadlock
    # where the addon was blocked from installing because it was waiting for
    # the MySQL chain, which itself needed the addon to provision the PVC.
  ]

  tags = {
    project = "zylkerkart"
  }
}