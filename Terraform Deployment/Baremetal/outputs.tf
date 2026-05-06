output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "storefront_url" {
  description = "URL to access the ZylkerKart storefront (via ALB)"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ssh_private_key" {
  description = "Private SSH key (auto-saved to .pem file)"
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}

# ── Public IPs (all instances are in public subnets) ─────────────────────────

output "storefront_public_ip" {
  description = "Public IP of the Storefront instance"
  value       = aws_instance.storefront.public_ip
}

output "mysql_public_ip" {
  description = "Public IP of the MySQL instance"
  value       = aws_instance.mysql.public_ip
}

output "redis_public_ip" {
  description = "Public IP of the Redis instance"
  value       = aws_instance.redis.public_ip
}

output "product_service_public_ip" {
  description = "Public IP of the Product Service instance"
  value       = aws_instance.product_service.public_ip
}

output "order_service_public_ip" {
  description = "Public IP of the Order Service instance"
  value       = aws_instance.order_service.public_ip
}

output "search_service_public_ip" {
  description = "Public IP of the Search Service instance"
  value       = aws_instance.search_service.public_ip
}

output "payment_service_public_ip" {
  description = "Public IP of the Payment Service instance"
  value       = aws_instance.payment_service.public_ip
}

output "auth_service_public_ip" {
  description = "Public IP of the Auth Service instance"
  value       = aws_instance.auth_service.public_ip
}

# ── Private IPs ──────────────────────────────────────────────────────────────

output "mysql_private_ip" {
  description = "Private IP of the MySQL instance"
  value       = aws_instance.mysql.private_ip
}

output "redis_private_ip" {
  description = "Private IP of the Redis instance"
  value       = aws_instance.redis.private_ip
}

# ── SSH Commands ─────────────────────────────────────────────────────────────

output "ssh_commands" {
  description = "SSH commands for all instances"
  value = {
    storefront      = "ssh -i ${var.key_pair_name}.pem ubuntu@${aws_instance.storefront.public_ip}"
    mysql           = "ssh -i ${var.key_pair_name}.pem ubuntu@${aws_instance.mysql.public_ip}"
    redis           = "ssh -i ${var.key_pair_name}.pem ubuntu@${aws_instance.redis.public_ip}"
    product_service = "ssh -i ${var.key_pair_name}.pem ubuntu@${aws_instance.product_service.public_ip}"
    order_service   = "ssh -i ${var.key_pair_name}.pem ubuntu@${aws_instance.order_service.public_ip}"
    search_service  = "ssh -i ${var.key_pair_name}.pem ubuntu@${aws_instance.search_service.public_ip}"
    payment_service = "ssh -i ${var.key_pair_name}.pem ubuntu@${aws_instance.payment_service.public_ip}"
    auth_service    = "ssh -i ${var.key_pair_name}.pem ubuntu@${aws_instance.auth_service.public_ip}"
  }
}

# ── SSM Monitoring ───────────────────────────────────────────────────────────

output "ssm_check_commands" {
  description = "AWS CLI commands to check SSM association execution status"
  value = {
    list_associations     = "aws ssm list-associations --association-filter-list 'key=AssociationName,value=zylkerkart'"
    mysql_executions      = "aws ssm describe-association-executions --association-id ${aws_ssm_association.mysql_setup.association_id}"
    redis_executions      = "aws ssm describe-association-executions --association-id ${aws_ssm_association.redis_setup.association_id}"
    product_executions    = "aws ssm describe-association-executions --association-id ${aws_ssm_association.product_setup.association_id}"
    order_executions      = "aws ssm describe-association-executions --association-id ${aws_ssm_association.order_setup.association_id}"
    search_executions     = "aws ssm describe-association-executions --association-id ${aws_ssm_association.search_setup.association_id}"
    payment_executions    = "aws ssm describe-association-executions --association-id ${aws_ssm_association.payment_setup.association_id}"
    auth_executions       = "aws ssm describe-association-executions --association-id ${aws_ssm_association.auth_setup.association_id}"
    storefront_executions = "aws ssm describe-association-executions --association-id ${aws_ssm_association.storefront_setup.association_id}"
  }
}
