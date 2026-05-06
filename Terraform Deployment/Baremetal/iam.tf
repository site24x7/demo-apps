# ── IAM Role for EC2 instances (SSM access) ──────────────────────────────────
resource "aws_iam_role" "ec2_ssm" {
  name = "zylkerkart-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name    = "zylkerkart-ec2-ssm-role"
    Project = "ZylkerKart"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ssm_s3_logs" {
  name = "zylkerkart-ssm-s3-logs"
  role = aws_iam_role.ec2_ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.ssm_logs.arn,
          "${aws_s3_bucket.ssm_logs.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ssm" {
  name = "zylkerkart-ssm-profile"
  role = aws_iam_role.ec2_ssm.name

  tags = {
    Name    = "zylkerkart-ssm-profile"
    Project = "ZylkerKart"
  }
}
