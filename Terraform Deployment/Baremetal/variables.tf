variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "key_pair_name" {
  description = "Name of the AWS key pair to use for SSH access"
  type        = string
  default     = "vinoth_pm_demo"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into instances. Restrict to your IP in production (e.g. '1.2.3.4/32'). No default — must be set explicitly."
  type        = string
  default     = "0.0.0.0/0"
}

variable "artifact_version" {
  description = "ZylkerKart artifact version to download from GitHub releases (e.g. 'v1.0.0')"
  type        = string
  default     = "v1.0.1"
}

# Instance types
variable "instance_type_mysql" {
  description = "EC2 instance type for MySQL"
  type        = string
  default     = "t3.large"
}

variable "instance_type_default" {
  description = "EC2 instance type for all other services"
  type        = string
  default     = "t3.small"
}

variable "site24x7_key" {
  description = "Site24x7 device key for agent installation"
  type        = string
  default     = ""
  sensitive   = true
}
