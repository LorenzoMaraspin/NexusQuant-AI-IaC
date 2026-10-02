###############################################################################
# Module: s3_history — private S3 bucket for historical market data exports
# Encryption: SSE-S3 (AES256, AWS-managed keys). No customer-managed KMS key.
###############################################################################

resource "aws_s3_bucket" "history" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = {
    Name        = var.bucket_name
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket_ownership_controls" "history" {
  bucket = aws_s3_bucket.history.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "history" {
  bucket = aws_s3_bucket.history.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "history" {
  bucket = aws_s3_bucket.history.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "history" {
  bucket = aws_s3_bucket.history.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_days
    }
  }
}

# Deny any request that is not made over TLS.
data "aws_iam_policy_document" "tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.history.arn,
      "${aws_s3_bucket.history.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "history" {
  bucket = aws_s3_bucket.history.id
  policy = data.aws_iam_policy_document.tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.history]
}
