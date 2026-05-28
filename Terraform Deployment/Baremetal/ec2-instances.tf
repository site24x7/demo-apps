# ── MySQL ─────────────────────────────────────────────────────────────────────
resource "aws_instance" "mysql" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_mysql
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.mysql.id]
  key_name               = aws_key_pair.generated.key_name
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  depends_on = [aws_route_table_association.public_a]

  tags = {
    Name    = "zylkerkart-mysql"
    Service = "mysql"
  }
}

# ── Redis ─────────────────────────────────────────────────────────────────────
resource "aws_instance" "redis" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_default
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.redis.id]
  key_name               = aws_key_pair.generated.key_name
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  depends_on = [aws_route_table_association.public_a]

  tags = {
    Name    = "zylkerkart-redis"
    Service = "redis"
  }
}

# ── Product Service ───────────────────────────────────────────────────────────
resource "aws_instance" "product_service" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_default
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.product.id]
  key_name               = aws_key_pair.generated.key_name
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  depends_on = [aws_route_table_association.public_a]

  tags = {
    Name    = "zylkerkart-product-service"
    Service = "product-service"
  }
}

# ── Order Service ─────────────────────────────────────────────────────────────
resource "aws_instance" "order_service" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_default
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.order.id]
  key_name               = aws_key_pair.generated.key_name
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  depends_on = [aws_route_table_association.public_a]

  tags = {
    Name    = "zylkerkart-order-service"
    Service = "order-service"
  }
}

# ── Search Service ────────────────────────────────────────────────────────────
resource "aws_instance" "search_service" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_default
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.search.id]
  key_name               = aws_key_pair.generated.key_name
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  depends_on = [aws_route_table_association.public_a]

  tags = {
    Name    = "zylkerkart-search-service"
    Service = "search-service"
  }
}

# ── Payment Service ───────────────────────────────────────────────────────────
resource "aws_instance" "payment_service" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_default
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.payment.id]
  key_name               = aws_key_pair.generated.key_name
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  depends_on = [aws_route_table_association.public_a]

  tags = {
    Name    = "zylkerkart-payment-service"
    Service = "payment-service"
  }
}

# ── Auth Service ──────────────────────────────────────────────────────────────
resource "aws_instance" "auth_service" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_default
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.auth.id]
  key_name               = aws_key_pair.generated.key_name
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  depends_on = [aws_route_table_association.public_a]

  tags = {
    Name    = "zylkerkart-auth-service"
    Service = "auth-service"
  }
}

# ── Storefront ────────────────────────────────────────────────────────────────
resource "aws_instance" "storefront" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_default
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.storefront.id]
  key_name               = aws_key_pair.generated.key_name
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  tags = {
    Name    = "zylkerkart-storefront"
    Service = "storefront"
  }
}
