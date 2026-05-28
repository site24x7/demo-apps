locals {
  vpc_cidr = "10.0.0.0/16"
}

# ── ALB ───────────────────────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "zylkerkart-sg-alb"
  description = "Security group for the Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "zylkerkart-sg-alb"
  }
}

# ── MySQL ─────────────────────────────────────────────────────────────────────
resource "aws_security_group" "mysql" {
  name        = "zylkerkart-sg-mysql"
  description = "Security group for MySQL"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MySQL from backend services"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "zylkerkart-sg-mysql"
  }
}

# ── Redis ─────────────────────────────────────────────────────────────────────
resource "aws_security_group" "redis" {
  name        = "zylkerkart-sg-redis"
  description = "Security group for Redis"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Redis from backend services"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "zylkerkart-sg-redis"
  }
}

# ── Product Service ───────────────────────────────────────────────────────────
resource "aws_security_group" "product" {
  name        = "zylkerkart-sg-product"
  description = "Security group for Product Service"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Product Service from Storefront"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "zylkerkart-sg-product"
  }
}

# ── Order Service ─────────────────────────────────────────────────────────────
resource "aws_security_group" "order" {
  name        = "zylkerkart-sg-order"
  description = "Security group for Order Service"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Order Service from Storefront"
    from_port   = 8082
    to_port     = 8082
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "zylkerkart-sg-order"
  }
}

# ── Search Service ────────────────────────────────────────────────────────────
resource "aws_security_group" "search" {
  name        = "zylkerkart-sg-search"
  description = "Security group for Search Service"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Search Service from Storefront"
    from_port   = 8083
    to_port     = 8083
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "zylkerkart-sg-search"
  }
}

# ── Payment Service ───────────────────────────────────────────────────────────
resource "aws_security_group" "payment" {
  name        = "zylkerkart-sg-payment"
  description = "Security group for Payment Service"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Payment Service from Storefront and Order Service"
    from_port   = 8084
    to_port     = 8084
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "zylkerkart-sg-payment"
  }
}

# ── Auth Service ──────────────────────────────────────────────────────────────
resource "aws_security_group" "auth" {
  name        = "zylkerkart-sg-auth"
  description = "Security group for Auth Service"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Auth Service from Storefront and Order Service"
    from_port   = 8085
    to_port     = 8085
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "zylkerkart-sg-auth"
  }
}

# ── Storefront ────────────────────────────────────────────────────────────────
resource "aws_security_group" "storefront" {
  name        = "zylkerkart-sg-storefront"
  description = "Security group for Storefront (accepts HTTP only from ALB)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Direct HTTP access"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "zylkerkart-sg-storefront"
  }
}
