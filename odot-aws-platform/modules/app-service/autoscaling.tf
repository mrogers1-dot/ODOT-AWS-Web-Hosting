# modules/app-service/autoscaling.tf
#
# ECS Service Auto-Scaling configuration for the app-service module.
#
# Provisions:
#   - Application Auto Scaling target (min=2, max=50 tasks)
#   - Scale-out policies: CPU > 70% OR memory > 70% for 3 minutes (180s)
#   - Scale-in policies: CPU < 30% AND memory < 30% for 10 minutes (600s)
#
# The scale-out uses CloudWatch alarms that trigger independently (OR logic)
# so that either high CPU or high memory causes a scale-out event.
#
# The scale-in uses a composite alarm requiring BOTH CPU and memory to be
# below threshold (AND logic) to avoid premature scale-in when only one
# metric has dropped.
#
# Requirements: 4.4, 4.5, 4.6

# ── Auto Scaling Target ───────────────────────────────────────────────────────
#
# Registers the ECS service as a scalable target with Application Auto Scaling.
# min_capacity = 2 ensures high availability (at least 2 tasks across AZs).
# max_capacity = 50 allows handling seasonal traffic spikes.
resource "aws_appautoscaling_target" "ecs" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${var.cluster_name}/${var.app_name}-${var.stage}"
  min_capacity       = 2
  max_capacity       = 50

  tags = merge(local.default_tags, var.tags)
}

# ── Scale-Out Policies ────────────────────────────────────────────────────────
#
# Scale-out triggers when CPU > 70% OR memory > 70% for 3 consecutive minutes.
# Each metric has its own alarm and step scaling policy so that either condition
# independently triggers scale-out (OR logic).

# Scale-out policy for high CPU utilization
resource "aws_appautoscaling_policy" "scale_out_cpu" {
  name               = "odot-${var.app_name}-${var.stage}-scale-out-cpu"
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 180
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 2
    }
  }
}

# Scale-out policy for high memory utilization
resource "aws_appautoscaling_policy" "scale_out_memory" {
  name               = "odot-${var.app_name}-${var.stage}-scale-out-memory"
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 180
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 2
    }
  }
}

# ── Scale-Out CloudWatch Alarms ───────────────────────────────────────────────
#
# These alarms trigger the scale-out policies when thresholds are breached.
# Period = 180s (3 minutes) with evaluation_periods = 1 means the alarm fires
# after 3 consecutive minutes of the metric exceeding the threshold.

# CPU utilization > 70% for 3 minutes triggers scale-out
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "odot-${var.app_name}-${var.stage}-cpu-high-scale-out"
  alarm_description   = "ECS service ${var.app_name}-${var.stage} CPU utilization exceeds 70% for 3 minutes — triggers scale-out"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 180
  statistic           = "Average"
  threshold           = 70

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = "${var.app_name}-${var.stage}"
  }

  alarm_actions = [aws_appautoscaling_policy.scale_out_cpu.arn]

  tags = merge(local.default_tags, var.tags, {
    Name = "odot-${var.app_name}-${var.stage}-cpu-high-scale-out"
  })
}

# Memory utilization > 70% for 3 minutes triggers scale-out
resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "odot-${var.app_name}-${var.stage}-memory-high-scale-out"
  alarm_description   = "ECS service ${var.app_name}-${var.stage} memory utilization exceeds 70% for 3 minutes — triggers scale-out"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 180
  statistic           = "Average"
  threshold           = 70

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = "${var.app_name}-${var.stage}"
  }

  alarm_actions = [aws_appautoscaling_policy.scale_out_memory.arn]

  tags = merge(local.default_tags, var.tags, {
    Name = "odot-${var.app_name}-${var.stage}-memory-high-scale-out"
  })
}

# ── Scale-In Policy ───────────────────────────────────────────────────────────
#
# Scale-in triggers when BOTH CPU < 30% AND memory < 30% for 10 consecutive
# minutes. A composite alarm enforces the AND logic — both individual alarms
# must be in ALARM state before scale-in occurs.

# Scale-in policy — removes tasks when utilization is low
resource "aws_appautoscaling_policy" "scale_in" {
  name               = "odot-${var.app_name}-${var.stage}-scale-in"
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 300
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

# CPU utilization < 30% for 10 minutes (individual alarm for composite)
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "odot-${var.app_name}-${var.stage}-cpu-low-scale-in"
  alarm_description   = "ECS service ${var.app_name}-${var.stage} CPU utilization below 30% for 10 minutes"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 600
  statistic           = "Average"
  threshold           = 30

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = "${var.app_name}-${var.stage}"
  }

  # No direct alarm_actions — the composite alarm handles the scale-in trigger
  tags = merge(local.default_tags, var.tags, {
    Name = "odot-${var.app_name}-${var.stage}-cpu-low-scale-in"
  })
}

# Memory utilization < 30% for 10 minutes (individual alarm for composite)
resource "aws_cloudwatch_metric_alarm" "memory_low" {
  alarm_name          = "odot-${var.app_name}-${var.stage}-memory-low-scale-in"
  alarm_description   = "ECS service ${var.app_name}-${var.stage} memory utilization below 30% for 10 minutes"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 600
  statistic           = "Average"
  threshold           = 30

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = "${var.app_name}-${var.stage}"
  }

  # No direct alarm_actions — the composite alarm handles the scale-in trigger
  tags = merge(local.default_tags, var.tags, {
    Name = "odot-${var.app_name}-${var.stage}-memory-low-scale-in"
  })
}

# Composite alarm: triggers scale-in only when BOTH CPU AND memory are low.
# This prevents premature scale-in when only one metric has dropped while
# the other remains elevated.
resource "aws_cloudwatch_composite_alarm" "scale_in" {
  alarm_name        = "odot-${var.app_name}-${var.stage}-scale-in-composite"
  alarm_description = "Composite alarm for scale-in: triggers when both CPU and memory are below 30% for 10 minutes"

  alarm_rule = "ALARM(${aws_cloudwatch_metric_alarm.cpu_low.alarm_name}) AND ALARM(${aws_cloudwatch_metric_alarm.memory_low.alarm_name})"

  alarm_actions = [aws_appautoscaling_policy.scale_in.arn]

  tags = merge(local.default_tags, var.tags, {
    Name = "odot-${var.app_name}-${var.stage}-scale-in-composite"
  })
}
