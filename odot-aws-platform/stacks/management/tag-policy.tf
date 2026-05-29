# stacks/management/tag-policy.tf
#
# AWS Organizations Tag Policy enforcing the three required tags at the OU level.
# This prevents untagged resources from being created in any account under the
# ODOT-Web organizational unit.
#
# Requirements: 22.1, 22.2, 22.3

resource "aws_organizations_policy" "tag_policy" {
  name        = "odot-required-tags"
  description = "Enforces Environment, Project, and Owner tags on all taggable resources in the ODOT-Web OU"
  type        = "TAG_POLICY"

  content = jsonencode({
    tags = {
      Environment = {
        tag_key = {
          "@@assign" = "Environment"
        }
        tag_value = {
          "@@assign" = ["dev", "test", "prod"]
        }
        enforced_for = {
          "@@assign" = ["ec2:*", "ecs:*", "elasticloadbalancing:*", "s3:bucket", "rds:*", "lambda:*", "kms:*", "logs:*", "sns:*", "dynamodb:*", "ecr:*"]
        }
      }
      Project = {
        tag_key = {
          "@@assign" = "Project"
        }
        enforced_for = {
          "@@assign" = ["ec2:*", "ecs:*", "elasticloadbalancing:*", "s3:bucket", "rds:*", "lambda:*", "kms:*", "logs:*", "sns:*", "dynamodb:*", "ecr:*"]
        }
      }
      Owner = {
        tag_key = {
          "@@assign" = "Owner"
        }
        enforced_for = {
          "@@assign" = ["ec2:*", "ecs:*", "elasticloadbalancing:*", "s3:bucket", "rds:*", "lambda:*", "kms:*", "logs:*", "sns:*", "dynamodb:*", "ecr:*"]
        }
      }
    }
  })

  tags = {
    Environment = "management"
    Project     = "ODOTWebHosting"
    Owner       = "odot-platform-team"
  }
}

resource "aws_organizations_policy_attachment" "tag_policy" {
  policy_id = aws_organizations_policy.tag_policy.id
  target_id = var.odot_web_ou_id
}

variable "odot_web_ou_id" {
  description = "ID of the ODOT-Web organizational unit to attach the tag policy to."
  type        = string
}
