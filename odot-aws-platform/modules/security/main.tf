# modules/security/main.tf
#
# Provisions account-wide security services for one ODOT AWS account:
#   - KMS Customer Managed Key (CMK) with automatic annual rotation
#   - GuardDuty detector
#   - Security Hub with AWS Foundational Security Best Practices standard
#   - AWS Config recorder, delivery channel, and managed Config rules
#   - Macie with a scheduled classification job covering all S3 buckets
#
# SCP JSON policy documents live under policies/ and are applied at the
# Organizations level by the management account stack — they are not
# Terraform resources in this module, but are co-located here for
# version-control and review purposes.
#
# Requirements: 1.2, 1.3, 9.1, 9.2, 9.3, 9.4, 9.5

locals {
  # Merge caller-supplied tags with module-level defaults so that every
  # resource always carries the three mandatory tags (Environment, Project, Owner).
  default_tags = {
    Project = "ODOTWebHosting"
    Owner   = "odot-platform-team"
  }
  merged_tags = merge(local.default_tags, var.tags)
}

# ── KMS Customer Managed Key ──────────────────────────────────────────────────
#
# One CMK per account. Annual key rotation is mandatory (Requirement 9.5).
# deletion_window_in_days = 30 gives the platform team time to recover if a
# key is accidentally scheduled for deletion.
resource "aws_kms_key" "this" {
  description             = "ODOT ${var.account_type} account CMK"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = local.merged_tags
}

# Friendly alias so other modules can reference the key by a predictable name
# rather than the opaque key ID.
resource "aws_kms_alias" "this" {
  name          = "alias/odot-${var.account_type}"
  target_key_id = aws_kms_key.this.key_id
}

# ── GuardDuty ─────────────────────────────────────────────────────────────────
#
# Enables the GuardDuty detector for continuous threat detection.
# Findings are forwarded to Security Hub via the native integration
# (no explicit publishing destination resource is required when both
# services are enabled in the same account).
resource "aws_guardduty_detector" "this" {
  enable = true

  tags = local.merged_tags
}

# ── Security Hub ──────────────────────────────────────────────────────────────
#
# aws_securityhub_account enables Security Hub in the account.
# The FSBP standards subscription is created after Security Hub is enabled.
resource "aws_securityhub_account" "this" {
  tags = local.merged_tags
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:aws:securityhub:us-east-2::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.this]
}

# NIST 800-53 Rev 5 standard — provides compliance mapping for state-government
# audit requirements. Enables Security Hub controls aligned to NIST control families.
# Requirement 19.1
resource "aws_securityhub_standards_subscription" "nist" {
  standards_arn = "arn:aws:securityhub:us-east-2::standards/nist-800-53/v/5.0.0"

  depends_on = [aws_securityhub_account.this]
}

# ── AWS Config ────────────────────────────────────────────────────────────────
#
# IAM role that allows Config to call AWS APIs on our behalf and write
# delivery snapshots to the S3 bucket.
resource "aws_iam_role" "config" {
  name        = "odot-config-role-${var.account_type}"
  description = "IAM role assumed by AWS Config in the ${var.account_type} account"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowConfigAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.merged_tags
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Configuration recorder — captures resource configuration changes.
# all_supported = true records all supported resource types.
# include_global_resource_types = true captures IAM and other global resources.
resource "aws_config_configuration_recorder" "this" {
  name     = "odot-config-${var.account_type}"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

# Delivery channel — sends configuration snapshots and history to S3.
# Must be created before the recorder status resource enables recording.
resource "aws_config_delivery_channel" "this" {
  name           = "odot-config-channel-${var.account_type}"
  s3_bucket_name = var.config_s3_bucket_name

  depends_on = [aws_config_configuration_recorder.this]
}

# Recorder status — activates the recorder once the delivery channel is ready.
resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}

# ── AWS Config Managed Rules ──────────────────────────────────────────────────
#
# Four managed rules that enforce baseline security posture.
# All rules depend on the recorder status being enabled first.

resource "aws_config_config_rule" "vpc_default_sg_closed" {
  name = "vpc-default-security-group-closed"

  source {
    owner             = "AWS"
    source_identifier = "VPC_DEFAULT_SECURITY_GROUP_CLOSED"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

resource "aws_config_config_rule" "iam_no_inline_policy" {
  name = "iam-no-inline-policy"

  source {
    owner             = "AWS"
    source_identifier = "IAM_NO_INLINE_POLICY_CHECK"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

resource "aws_config_config_rule" "ecs_task_nonroot_user" {
  name = "ecs-task-definition-nonroot-user"

  source {
    owner             = "AWS"
    source_identifier = "ECS_TASK_DEFINITION_NONROOT_USER"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

resource "aws_config_config_rule" "ecs_task_memory_hard_limit" {
  name = "ecs-task-definition-memory-hard-limit"

  source {
    owner             = "AWS"
    source_identifier = "ECS_TASK_DEFINITION_MEMORY_HARD_LIMIT"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# ── Macie ─────────────────────────────────────────────────────────────────────
#
# Enables Macie for sensitive data discovery. The classification job runs
# daily and scans all S3 buckets in the account.
resource "aws_macie2_account" "this" {
  status                       = "ENABLED"
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

# Scheduled daily classification job covering all S3 buckets.
# bucket_criteria with no excludes block matches every bucket in the account.
resource "aws_macie2_classification_job" "this" {
  name     = "odot-macie-scan-${var.account_type}"
  job_type = "SCHEDULED"

  schedule_frequency {
    daily_schedule = true
  }

  s3_job_definition {
    bucket_criteria {
      excludes {
        and {
          simple_criterion {
            comparator = "NE"
            key        = "BUCKET_CREATED_AT"
            values     = ["1970-01-01T00:00:00Z"]
          }
        }
      }
    }
  }

  depends_on = [aws_macie2_account.this]
}
