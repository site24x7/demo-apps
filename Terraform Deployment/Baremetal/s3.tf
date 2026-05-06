# ── S3 Bucket for SSM execution logs ──────────────────────────────────────────

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "ssm_logs" {
  bucket = "zylkerkart-ssm-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "zylkerkart-ssm-logs"
    Project = "ZylkerKart"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ssm_logs" {
  bucket = aws_s3_bucket.ssm_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ssm_logs" {
  bucket = aws_s3_bucket.ssm_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_public_access_block" "ssm_logs" {
  bucket = aws_s3_bucket.ssm_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
