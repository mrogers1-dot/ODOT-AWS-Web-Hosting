# modules/app-service/main.tf
#
# Shared locals and configuration for the app-service module.
# Individual resource files (ecr.tf, task-definition.tf, alb.tf, etc.)
# reference these locals for consistent tagging and naming.
#
# Requirements: 1.6, 11.5

locals {
  # Merge caller-supplied tags with module-level defaults so every resource
  # always carries the three mandatory tags (Environment, Project, Owner).
  default_tags = {
    Project = "ODOTWebHosting"
    Owner   = "odot-platform-team"
  }
}

# ── ECS Task Execution Role ───────────────────────────────────────────────────
#
# IAM role assumed by the ECS agent to pull images from ECR and write logs
# to CloudWatch. This is NOT the task role (which the application code uses).
resource "aws_iam_role" "ecs_task_execution" {
  name        = "odot-ecs-task-${var.app_name}-${var.stage}"
  description = "ECS task execution role for ${var.app_name}-${var.stage}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.default_tags, var.tags)
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
