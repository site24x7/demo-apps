# ── S3 Bucket for SSM execution logs (optional, for troubleshooting) ──────────

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "ssm_logs" {
  count  = var.enable_ssm_logging ? 1 : 0
  bucket = "zylkerkart-ssm-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "zylkerkart-ssm-logs"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ssm_logs" {
  count  = var.enable_ssm_logging ? 1 : 0
  bucket = aws_s3_bucket.ssm_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ssm_logs" {
  count  = var.enable_ssm_logging ? 1 : 0
  bucket = aws_s3_bucket.ssm_logs[0].id

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
  count  = var.enable_ssm_logging ? 1 : 0
  bucket = aws_s3_bucket.ssm_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
