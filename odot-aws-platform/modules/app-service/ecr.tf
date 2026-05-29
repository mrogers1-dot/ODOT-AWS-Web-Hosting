# modules/app-service/ecr.tf
#
# Provisions an Amazon ECR repository for the application with:
#   - Image scanning on push (Requirement 5.2, Property 4)
#   - KMS encryption for all stored images (Requirement 5.3, Property 4)
#   - Lifecycle policy enforcing retention rules (Requirement 5.5, Property 5)
#
# The lifecycle policy contains exactly two rules:
#   Rule 1 — Tagged images: retain a maximum of 10 images. When the count
#            exceeds 10, the oldest tagged images are expired.
#   Rule 2 — Untagged images: expire any untagged image older than 7 days.
#            This prevents accumulation of intermediate/dangling layers.
#
# Requirements: 5.1, 5.2, 5.3, 5.5

locals {
  # ECR repository naming follows the convention: odot-{app_name}-{account_type}
  ecr_repository_name = "odot-${var.app_name}-${var.account_type}"
}

# ── ECR Repository ────────────────────────────────────────────────────────────
#
# One private ECR repository per application per account (Requirement 5.1).
# Scan-on-push triggers an Amazon Inspector vulnerability scan each time an
# image is pushed (Requirement 5.2). All images are encrypted at rest using
# a customer-managed KMS key (Requirement 5.3).
resource "aws_ecr_repository" "app" {
  name                 = local.ecr_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = merge(local.default_tags, var.tags, {
    Name = local.ecr_repository_name
  })
}

# ── ECR Lifecycle Policy ──────────────────────────────────────────────────────
#
# Exactly two rules enforce image retention (Requirement 5.5, Property 5):
#
#   Rule 1 (priority 1): Tagged images — retain at most 10 images. When the
#   count exceeds 10, the oldest tagged images are removed. This keeps the
#   repository lean while preserving recent deployable images.
#
#   Rule 2 (priority 2): Untagged images — expire images that have been
#   untagged for more than 7 days. Untagged images typically represent
#   intermediate build layers or images that have been superseded.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Retain a maximum of 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = [""]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countNumber = 7
          countUnit   = "days"
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
