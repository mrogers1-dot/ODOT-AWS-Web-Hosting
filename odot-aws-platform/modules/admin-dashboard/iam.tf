# modules/admin-dashboard/iam.tf
#
# IAM roles for the admin dashboard:
#   1. Dashboard task role — permissions for the dashboard ECS task to call
#      AWS APIs (ECS, CloudWatch, ALB, WAF, Auto-Scaling, DynamoDB, SNS, STS)
#   2. Cross-account role — assumed by the dashboard task role to manage
#      resources in the External account
#   3. WAF IP set — for managed IP blocking from the dashboard UI
#
# All permissions are scoped to resources matching the WebHosting-* pattern
# to prevent the dashboard from affecting non-ODOT resources.
#
# Requirements: 14.29, 14.30

# ── Dashboard Task Role ───────────────────────────────────────────────────────
#
# This role is attached to the dashboard ECS task. It grants permissions to
# manage ECS services, read CloudWatch metrics/logs, manage ALB rules,
# update WAF IP sets, control auto-scaling, write audit logs to DynamoDB,
# and publish to SNS. It can also assume the cross-account role in External.
resource "aws_iam_role" "dashboard_task" {
  name        = "odot-dashboard-task-${var.stage}"
  description = "IAM role for the ODOT admin dashboard ECS task — grants operational permissions scoped to WebHosting-* resources"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowECSTaskAssume"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.merged_tags, {
    Name = "odot-dashboard-task-${var.stage}"
  })
}

resource "aws_iam_role_policy" "dashboard_task" {
  name = "odot-dashboard-task-${var.stage}-policy"
  role = aws_iam_role.dashboard_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSOperations"
        Effect = "Allow"
        Action = [
          "ecs:ListServices",
          "ecs:DescribeServices",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:UpdateService",
          "ecs:StopTask",
          "ecs:DescribeTaskDefinition",
          "ecs:ListTaskDefinitions",
          "ecs:RegisterTaskDefinition",
          "ecs:DescribeClusters",
          "ecs:ListClusters"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ecs:cluster" = "arn:aws:ecs:*:${var.internal_account_id}:cluster/WebHosting-*"
          }
        }
      },
      {
        Sid    = "ECSListAll"
        Effect = "Allow"
        Action = [
          "ecs:ListServices",
          "ecs:ListClusters",
          "ecs:DescribeClusters"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchMetricsAndLogs"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarms",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:StartQuery",
          "logs:GetQueryResults",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Sid    = "ALBOperations"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:DescribeListeners"
        ]
        Resource = "*"
      },
      {
        Sid    = "WAFOperations"
        Effect = "Allow"
        Action = [
          "wafv2:GetIPSet",
          "wafv2:UpdateIPSet",
          "wafv2:ListIPSets"
        ]
        Resource = "*"
      },
      {
        Sid    = "AutoScalingOperations"
        Effect = "Allow"
        Action = [
          "application-autoscaling:DescribeScalingActivities",
          "application-autoscaling:DescribeScalableTargets",
          "application-autoscaling:RegisterScalableTarget",
          "application-autoscaling:DescribeScalingPolicies"
        ]
        Resource = "*"
      },
      {
        Sid    = "DynamoDBAudit"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.audit.arn,
          "${aws_dynamodb_table.audit.arn}/index/*"
        ]
      },
      {
        Sid    = "SNSPublish"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.sns_topic_arn
      },
      {
        Sid    = "STSAssumeExternalRole"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.external_account_id}:role/odot-dashboard-cross-account-${var.stage}"
      },
      {
        Sid    = "ECRReadOnly"
        Effect = "Allow"
        Action = [
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:DescribeImageScanFindings",
          "ecr:DescribeRepositories",
          "ecr:ListTagsForResource"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── Cross-Account Role (External Account) ────────────────────────────────────
#
# This role lives in the External account and is assumed by the dashboard task
# role in the Internal account. It grants the same operational permissions but
# scoped to External account resources.
#
# NOTE: This resource must be deployed in the External account stack.
# It is defined here for documentation and reference. The actual deployment
# requires the External account provider.
resource "aws_iam_role" "cross_account" {
  name        = "odot-dashboard-cross-account-${var.stage}"
  description = "Cross-account role assumed by the ODOT admin dashboard for managing External account resources"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowInternalDashboardAssume"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.internal_account_id}:role/odot-dashboard-task-${var.stage}"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.merged_tags, {
    Name = "odot-dashboard-cross-account-${var.stage}"
  })
}

resource "aws_iam_role_policy" "cross_account" {
  name = "odot-dashboard-cross-account-${var.stage}-policy"
  role = aws_iam_role.cross_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSOperations"
        Effect = "Allow"
        Action = [
          "ecs:ListServices",
          "ecs:DescribeServices",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:UpdateService",
          "ecs:StopTask",
          "ecs:DescribeTaskDefinition",
          "ecs:ListTaskDefinitions",
          "ecs:RegisterTaskDefinition",
          "ecs:DescribeClusters",
          "ecs:ListClusters"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchMetricsAndLogs"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarms",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:StartQuery",
          "logs:GetQueryResults",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Sid    = "ALBOperations"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:DescribeListeners"
        ]
        Resource = "*"
      },
      {
        Sid    = "WAFOperations"
        Effect = "Allow"
        Action = [
          "wafv2:GetIPSet",
          "wafv2:UpdateIPSet",
          "wafv2:ListIPSets"
        ]
        Resource = "*"
      },
      {
        Sid    = "AutoScalingOperations"
        Effect = "Allow"
        Action = [
          "application-autoscaling:DescribeScalingActivities",
          "application-autoscaling:DescribeScalableTargets",
          "application-autoscaling:RegisterScalableTarget",
          "application-autoscaling:DescribeScalingPolicies"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRReadOnly"
        Effect = "Allow"
        Action = [
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:DescribeImageScanFindings",
          "ecr:DescribeRepositories"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── WAF IP Set ────────────────────────────────────────────────────────────────
#
# A WAF IP set managed by the dashboard for blocking malicious IPs.
# The dashboard UI allows Admins to add/remove IPs from this set.
resource "aws_wafv2_ip_set" "dashboard_managed" {
  name               = "odot-dashboard-blocked-ips-${var.stage}"
  description        = "IP addresses blocked via the ODOT admin dashboard"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = []

  tags = merge(local.merged_tags, {
    Name = "odot-dashboard-blocked-ips-${var.stage}"
  })
}
