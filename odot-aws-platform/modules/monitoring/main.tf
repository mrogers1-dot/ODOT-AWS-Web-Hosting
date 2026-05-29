# modules/monitoring/main.tf
#
# Provisions CloudWatch dashboards, SNS topics, AWS Chatbot Slack integrations,
# SNS email subscriptions, and AWS Budgets for one account-stage combination.
#
# Resources created:
#   - SNS topic: `odot-alerts-{account_type}` with KMS encryption
#   - AWS Chatbot Slack channel configuration (one per account)
#   - CloudWatch dashboard per stage per account with 6 widgets
#   - AWS Budgets budget ($1000/month with 80% forecasted notification)
#   - SNS email subscription for ServiceNow/FortiSIEM
#
# The SNS topic serves as the central notification hub. CloudWatch alarms
# (created in the app-service module) publish to this topic. AWS Chatbot
# subscribes to the topic and forwards alerts to Slack. The email subscription
# provides a parallel path for ITSM integration.
#
# Requirements: 10.2, 10.4, 10.5, 11.1, 11.2

locals {
  # Merge caller-supplied tags with module-level defaults so every resource
  # always carries the three mandatory tags (Environment, Project, Owner).
  default_tags = {
    Project = "ODOTWebHosting"
    Owner   = "odot-platform-team"
  }
  merged_tags = merge(local.default_tags, var.tags)

  # Dashboard name follows the naming convention: odot-{account_type}-{stage}
  dashboard_name = "odot-${var.account_type}-${var.stage}"

  # SNS topic name: one per account (shared across stages within the account)
  sns_topic_name = "odot-alerts-${var.account_type}"

  # Chatbot configuration name
  chatbot_config_name = "odot-chatbot-${var.account_type}-${var.stage}"
}

# ── Data Sources ──────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── SNS Topic ─────────────────────────────────────────────────────────────────
#
# Central notification topic for all CloudWatch alarms in this account-stage.
# Encrypted with the account-level KMS key to protect alert content at rest.
# CloudWatch alarms (from app-service module) publish to this topic.
# AWS Chatbot and email subscriptions consume from this topic.
#
# Requirement 10.4: Alarms route through SNS → Chatbot → Slack
# Requirement 10.5: Alarms also route to email for ServiceNow/FortiSIEM
resource "aws_sns_topic" "alerts" {
  name              = local.sns_topic_name
  kms_master_key_id = var.kms_key_arn

  tags = merge(local.merged_tags, {
    Name = local.sns_topic_name
  })
}

# ── SNS Topic Policy ─────────────────────────────────────────────────────────
#
# Allows CloudWatch, Budgets, and EventBridge to publish to the SNS topic.
# Without this policy, alarm notifications and budget alerts would be rejected.
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${local.sns_topic_name}-policy"
    Statement = [
      {
        Sid       = "AllowCloudWatchAlarms"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "AllowBudgets"
        Effect    = "Allow"
        Principal = { Service = "budgets.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "AllowEventBridge"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ── SNS Email Subscription ───────────────────────────────────────────────────
#
# Email subscription for ServiceNow/FortiSIEM integration. The email endpoint
# receives all alarm notifications in parallel with the Slack channel.
# The subscription requires manual confirmation via the email link.
#
# Requirement 10.5: Route alarm notifications to email for ServiceNow/FortiSIEM
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── AWS Chatbot Slack Channel Configuration ───────────────────────────────────
#
# Configures AWS Chatbot to forward SNS notifications to the appropriate Slack
# channel. Internal account alarms go to #aws-alerts-internal, external to
# #aws-alerts-external.
#
# The IAM role grants Chatbot read-only access to CloudWatch for rendering
# alarm context in Slack messages.
#
# Requirement 10.4: Route alerts through AWS Chatbot to Slack
resource "aws_iam_role" "chatbot" {
  name = "odot-chatbot-${var.account_type}-${var.stage}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "chatbot.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.merged_tags, {
    Name = "odot-chatbot-${var.account_type}-${var.stage}"
  })
}

resource "aws_iam_role_policy" "chatbot" {
  name = "odot-chatbot-${var.account_type}-${var.stage}-policy"
  role = aws_iam_role.chatbot.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:Describe*",
          "cloudwatch:Get*",
          "cloudwatch:List*",
          "logs:Get*",
          "logs:List*",
          "logs:Describe*",
          "logs:TestMetricFilter",
          "logs:FilterLogEvents",
          "sns:Get*",
          "sns:List*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_chatbot_slack_channel_configuration" "alerts" {
  configuration_name = local.chatbot_config_name
  iam_role_arn       = aws_iam_role.chatbot.arn
  slack_channel_id   = var.slack_channel_id
  slack_team_id      = var.slack_workspace_id
  sns_topic_arns     = [aws_sns_topic.alerts.arn]

  logging_level = "INFO"

  tags = merge(local.merged_tags, {
    Name = local.chatbot_config_name
  })
}

# ── CloudWatch Dashboard ──────────────────────────────────────────────────────
#
# One dashboard per stage per account displaying key operational metrics.
# Widgets provide at-a-glance visibility into ECS cluster health and ALB
# traffic without requiring console login.
#
# Widgets:
#   1. ECS Running Task Count — shows active tasks across the cluster
#   2. ECS CPU Utilization — average CPU across all services
#   3. ECS Memory Utilization — average memory across all services
#   4. ALB Request Count — total inbound requests
#   5. ALB 5xx Error Rate — server-side error percentage
#   6. Active Alarm Count — number of alarms in ALARM state
#
# Requirement 10.2: CloudWatch dashboards per stage per account
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.dashboard_name

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "ECS Running Task Count"
          region = data.aws_region.current.id
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", "WebHosting-${title(var.stage)}"]
          ]
          period = 300
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "ECS CPU Utilization (%)"
          region = data.aws_region.current.id
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", "WebHosting-${title(var.stage)}"]
          ]
          period = 300
          stat   = "Average"
          view   = "timeSeries"
          yAxis = {
            left = { min = 0, max = 100 }
          }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "ECS Memory Utilization (%)"
          region = data.aws_region.current.id
          metrics = [
            ["AWS/ECS", "MemoryUtilization", "ClusterName", "WebHosting-${title(var.stage)}"]
          ]
          period = 300
          stat   = "Average"
          view   = "timeSeries"
          yAxis = {
            left = { min = 0, max = 100 }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "ALB Request Count"
          region = data.aws_region.current.id
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "app/odot-${var.account_type}-${var.stage}/*"]
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "ALB 5xx Error Rate"
          region = data.aws_region.current.id
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", "app/odot-${var.account_type}-${var.stage}/*"]
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "Active Alarms"
          region = data.aws_region.current.id
          metrics = [
            ["AWS/CloudWatch", "StateValue", "AlarmName", "odot-*-${var.stage}-*"]
          ]
          period = 300
          stat   = "Sum"
          view   = "singleValue"
        }
      }
    ]
  })
}

# ── AWS Budgets ───────────────────────────────────────────────────────────────
#
# Monthly cost budget with a forecasted spend notification at 80% threshold.
# The budget covers all resources in this account. When projected monthly spend
# reaches $800 (80% of $1000), a notification is sent to both the SNS topic
# (which routes to Slack via Chatbot) and the alert email.
#
# Requirement 11.1: Monthly cost budget of $1,000
# Requirement 11.2: Notification at 80% forecasted spend
resource "aws_budgets_budget" "monthly" {
  name         = "odot-${var.account_type}-${var.stage}-monthly-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.alerts.arn]
  }

  tags = merge(local.merged_tags, {
    Name = "odot-${var.account_type}-${var.stage}-monthly-budget"
  })
}
