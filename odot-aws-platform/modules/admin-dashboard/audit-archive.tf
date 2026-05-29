# modules/admin-dashboard/audit-archive.tf
#
# Tamper-evident audit trail export to S3 with Object Lock.
# Audit records from DynamoDB are exported daily to this bucket.
# Object Lock in COMPLIANCE mode ensures no one — including admins —
# can delete or modify audit records before the 365-day retention expires.
#
# Requirements: 28.1, 28.2, 28.3, 28.4

# ── Audit Archive S3 Bucket ───────────────────────────────────────────────────
#
# Object Lock must be enabled at bucket creation time (cannot be added later).
# COMPLIANCE mode prevents any principal from deleting objects before retention
# expiry — this is stronger than GOVERNANCE mode which allows bypass with
# s3:BypassGovernanceRetention permission.
resource "aws_s3_bucket" "audit_archive" {
  bucket              = "odot-dashboard-audit-archive-${var.stage}"
  object_lock_enabled = true

  tags = merge(local.merged_tags, {
    Name = "odot-dashboard-audit-archive-${var.stage}"
  })
}

resource "aws_s3_bucket_object_lock_configuration" "audit_archive" {
  bucket = aws_s3_bucket.audit_archive.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 365
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_archive" {
  bucket = aws_s3_bucket.audit_archive.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "audit_archive" {
  bucket = aws_s3_bucket.audit_archive.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "audit_archive" {
  bucket = aws_s3_bucket.audit_archive.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ── Bucket Policy: Deny Delete ────────────────────────────────────────────────
#
# Explicitly denies s3:DeleteObject and s3:PutObjectRetention (reduce retention)
# for ALL principals. Combined with COMPLIANCE mode Object Lock, this makes
# the audit trail provably immutable for the retention period.
resource "aws_s3_bucket_policy" "audit_archive_no_delete" {
  bucket = aws_s3_bucket.audit_archive.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyDeleteAndRetentionReduction"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
          "s3:PutObjectRetention"
        ]
        Resource = "${aws_s3_bucket.audit_archive.arn}/*"
      }
    ]
  })
}
