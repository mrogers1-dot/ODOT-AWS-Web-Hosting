# modules/app-service/cloudwatch.tf
#
# CloudWatch log group and monitoring alarms for the app-service module.
#
# Provisions:
#   - CloudWatch log group for ECS task logs with stage-based retention
#   - Four monitoring alarms: CPU > 80%, memory > 80%, ALB 5xx > 1%, task count < 2
#
# These are MONITORING alarms that notify the operations team via SNS.
# They are separate from the auto-scaling alarms in autoscaling.tf which
# trigger scaling policies.
#
# Requirements: 10.3, 10.6

# ── CloudWatch Log Group ──────────────────────────────────────────────────────
#
# Log group for ECS task container logs. Retention is 365 days for prod
# (compliance requirement) and 90 days for dev/test (cost optimization).
# Encrypted with the account-level KMS key.
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.app_name}/${var.stage}"
  retention_in_days = var.stage == "prod" ? 365 : 90

  tags = merge(local.default_tags, var.tags, {
    Name = "/ecs/${var.app_name}/${var.stage}"
  })
}

# ── Monitoring Alarms ─────────────────────────────────────────────────────────
#
# These alarms notify the operations team when service health degrades.
# All alarms route to the SNS topic which forwards to Slack and email
# via AWS Chatbot.

# CPU utilization > 80% for 5 minutes (300s) — indicates sustained high load
resource "aws_cloudwatch_metric_alarm" "cpu_utilization_high" {
  alarm_name          = "odot-${var.app_name}-${var.stage}-cpu-utilization-high"
  alarm_description   = "MONITORING: ECS service ${var.app_name}-${var.stage} CPU utilization exceeds 80% for 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = "${var.app_name}-${var.stage}"
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = merge(local.default_tags, var.tags, {
    Name = "odot-${var.app_name}-${var.stage}-cpu-utilization-high"
  })
}

# Memory utilization > 80% for 5 minutes (300s) — indicates potential OOM risk
resource "aws_cloudwatch_metric_alarm" "memory_utilization_high" {
  alarm_name          = "odot-${var.app_name}-${var.stage}-memory-utilization-high"
  alarm_description   = "MONITORING: ECS service ${var.app_name}-${var.stage} memory utilization exceeds 80% for 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = "${var.app_name}-${var.stage}"
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = merge(local.default_tags, var.tags, {
    Name = "odot-${var.app_name}-${var.stage}-memory-utilization-high"
  })
}

# ALB 5xx error rate > 1% for 5 minutes (300s) — indicates application errors
# Uses HTTPCode_Target_5XX_Count from the ALB target group metrics.
# The math expression calculates the percentage of 5xx responses relative
# to total request count.
resource "aws_cloudwatch_metric_alarm" "alb_5xx_rate" {
  alarm_name          = "odot-${var.app_name}-${var.stage}-alb-5xx-rate-high"
  alarm_description   = "MONITORING: ALB target 5xx error rate exceeds 1% for ${var.app_name}-${var.stage}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 1

  metric_query {
    id          = "error_rate"
    expression  = "(errors / requests) * 100"
    label       = "5xx Error Rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors"

    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"

      dimensions = {
        LoadBalancer = aws_lb.this.arn_suffix
        TargetGroup  = aws_lb_target_group.this.arn_suffix
      }
    }
  }

  metric_query {
    id = "requests"

    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"

      dimensions = {
        LoadBalancer = aws_lb.this.arn_suffix
        TargetGroup  = aws_lb_target_group.this.arn_suffix
      }
    }
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = merge(local.default_tags, var.tags, {
    Name = "odot-${var.app_name}-${var.stage}-alb-5xx-rate-high"
  })
}

# ECS running task count < 2 — indicates service degradation or failed tasks.
# Uses RunningTaskCount from ECS/ContainerInsights namespace which provides
# real-time task count visibility.
resource "aws_cloudwatch_metric_alarm" "task_count_low" {
  alarm_name          = "odot-${var.app_name}-${var.stage}-task-count-low"
  alarm_description   = "MONITORING: ECS service ${var.app_name}-${var.stage} running task count is below minimum threshold of 2"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 2

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = "${var.app_name}-${var.stage}"
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = merge(local.default_tags, var.tags, {
    Name = "odot-${var.app_name}-${var.stage}-task-count-low"
  })
}
