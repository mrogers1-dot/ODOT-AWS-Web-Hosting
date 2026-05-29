# modules/app-service/ecs-service.tf
#
# Provisions the ECS Fargate service that ties together the task definition,
# cluster, ALB target group, and security groups.
#
# Key behaviors:
#   - Fargate launch type with awsvpc networking
#   - Deployment circuit breaker enabled for automatic rollback on failure
#   - Capacity provider strategy varies by stage and runtime:
#     * Dev/Test Linux: FARGATE_SPOT (weight=1, base=1) + FARGATE (weight=0)
#     * Prod or Windows: FARGATE only (weight=1)
#   - Tasks distributed across private subnets (multi-AZ)
#   - Load balancer integration via ALB target group
#
# Requirements: 4.1, 4.3, 5.1, 7.3, 11.3

locals {
  # Service name follows the convention: {app_name}-{stage}
  service_name = "${var.app_name}-${var.stage}"

  # Windows tasks always use FARGATE (Spot not reliably supported for Windows).
  # Prod stage always uses FARGATE for reliability.
  # Dev/Test Linux tasks use FARGATE_SPOT for cost savings.
  use_spot = var.runtime == "linux" && var.stage != "prod"
}

# ── ECS Service ───────────────────────────────────────────────────────────────
#
# The ECS service maintains the desired count of running tasks, handles
# rolling deployments, and integrates with the ALB for traffic distribution.
# The deployment circuit breaker automatically rolls back failed deployments.
resource "aws_ecs_service" "app" {
  name            = local.service_name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2

  # Capacity provider strategy — determines Fargate vs Fargate Spot usage.
  # Dev/Test Linux: primarily Spot with base=1 on-demand for reliability.
  # Prod or Windows: on-demand Fargate only.
  dynamic "capacity_provider_strategy" {
    for_each = local.use_spot ? [1] : []
    content {
      capacity_provider = "FARGATE_SPOT"
      weight            = 1
      base              = 1
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = local.use_spot ? [1] : []
    content {
      capacity_provider = "FARGATE"
      weight            = 0
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = local.use_spot ? [] : [1]
    content {
      capacity_provider = "FARGATE"
      weight            = 1
      base              = 0
    }
  }

  # awsvpc network configuration — tasks get their own ENI in private subnets
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  # ALB integration — register tasks with the target group for load balancing
  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.app_name
    container_port   = var.container_port
  }

  # Deployment circuit breaker — automatically rolls back failed deployments
  # rather than leaving the service in a degraded state.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Ensure the ALB listener is created before the service attempts to register
  # tasks with the target group.
  depends_on = [aws_lb_listener.https]

  tags = merge(local.default_tags, var.tags, {
    Name = local.service_name
  })
}
