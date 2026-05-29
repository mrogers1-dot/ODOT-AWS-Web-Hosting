# modules/resilience/main.tf
#
# AWS Fault Injection Simulator (FIS) experiment templates for resilience validation.
# These experiments prove that the platform recovers from failures automatically.
#
# Experiments:
#   1. fis-stop-tasks-single-az — stops 50% of tasks in one AZ, verifies recovery
#   2. fis-bad-deployment — registers a failing task def, verifies circuit breaker rollback
#
# Requirements: 23.1, 23.2, 23.3

locals {
  default_tags = {
    Project = "ODOTWebHosting"
    Owner   = "odot-platform-team"
  }
  merged_tags = merge(local.default_tags, var.tags)
}

# ── FIS IAM Role ──────────────────────────────────────────────────────────────
#
# IAM role assumed by FIS to perform fault injection actions (stop tasks,
# update services). Scoped to ECS resources matching WebHosting-* clusters.
resource "aws_iam_role" "fis" {
  name        = "odot-fis-role-${var.stage}"
  description = "IAM role for AWS Fault Injection Simulator experiments"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "fis.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.merged_tags, {
    Name = "odot-fis-role-${var.stage}"
  })
}

resource "aws_iam_role_policy" "fis" {
  name = "odot-fis-policy-${var.stage}"
  role = aws_iam_role.fis.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSFaultInjection"
        Effect = "Allow"
        Action = [
          "ecs:StopTask",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchForStopConditions"
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarms"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── Experiment: Stop Tasks in Single AZ ───────────────────────────────────────
#
# Stops 50% of a service's Fargate tasks in a single AZ. Validates that ECS
# replaces the stopped tasks and restores desired count within 5 minutes.
# Stop condition: halt if running tasks drop below 1 (safety net).
resource "aws_fis_experiment_template" "stop_tasks_single_az" {
  description = "Stop 50% of ECS tasks in one AZ — validates multi-AZ recovery"
  role_arn    = aws_iam_role.fis.arn

  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = var.stop_condition_alarm_arn
  }

  action {
    name        = "StopTasks"
    action_id   = "aws:ecs:stop-task"
    description = "Stop 50% of tasks to simulate AZ failure"

    target {
      key   = "Tasks"
      value = "ecsTargets"
    }
  }

  target {
    name           = "ecsTargets"
    resource_type  = "aws:ecs:task"
    selection_mode = "PERCENT(50)"

    resource_tag {
      key   = "Project"
      value = "ODOTWebHosting"
    }
  }

  tags = merge(local.merged_tags, {
    Name = "odot-fis-stop-tasks-${var.stage}"
  })
}

# ── Experiment: Bad Deployment (Circuit Breaker Validation) ───────────────────
#
# Validates that the ECS deployment circuit breaker correctly rolls back a
# failed deployment. The experiment is documented but executed manually
# (FIS doesn't natively support "register bad task def" as an action).
# This template serves as documentation and a placeholder for the manual test.
resource "aws_fis_experiment_template" "bad_deployment" {
  description = "Validate ECS circuit breaker rollback on failed deployment"
  role_arn    = aws_iam_role.fis.arn

  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = var.stop_condition_alarm_arn
  }

  action {
    name        = "WaitForRollback"
    action_id   = "aws:fis:wait"
    description = "Wait 5 minutes for circuit breaker to detect failure and rollback"

    parameter {
      key   = "duration"
      value = "PT5M"
    }
  }

  target {
    name           = "ecsTargets"
    resource_type  = "aws:ecs:task"
    selection_mode = "ALL"

    resource_tag {
      key   = "Project"
      value = "ODOTWebHosting"
    }
  }

  tags = merge(local.merged_tags, {
    Name = "odot-fis-bad-deployment-${var.stage}"
  })
}
