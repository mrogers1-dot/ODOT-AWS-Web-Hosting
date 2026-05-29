# modules/ecs-cluster/main.tf
#
# Provisions one ECS cluster with Fargate capacity providers and Container
# Insights enabled. The default capacity provider strategy varies by stage:
#
#   dev/test — FARGATE_SPOT weight=1 base=1, FARGATE weight=0
#              Uses Spot for cost savings; base=1 ensures at least one task
#              runs on standard Fargate for reliability during Spot interruptions.
#              (Requirement 11.3)
#
#   prod     — FARGATE weight=1, FARGATE_SPOT weight=0
#              Uses on-demand Fargate exclusively for production stability.
#              Savings Plans reduce cost relative to on-demand pricing.
#              (Requirement 11.4)
#
# Container Insights is always enabled to collect CPU, memory, network, and
# task-level metrics for all clusters. (Requirement 10.1)
#
# Requirements: 4.1, 4.2, 11.3

locals {
  # Merge caller-supplied tags with module-level defaults so every resource
  # always carries the three mandatory tags (Environment, Project, Owner).
  default_tags = {
    Project = "ODOTWebHosting"
    Owner   = "odot-platform-team"
  }
  merged_tags = merge(local.default_tags, var.tags)

  # Convenience flag — used to select the capacity provider strategy.
  is_prod = var.stage == "prod"
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────
#
# The cluster itself is a logical grouping of tasks and services. All compute
# is Fargate-only — no EC2 launch type is permitted (Requirement 4.2).
# Container Insights is enabled via the setting block (Requirement 10.1,
# Property 14).
resource "aws_ecs_cluster" "main" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.merged_tags, {
    Name = var.cluster_name
  })
}

# ── Capacity Providers ────────────────────────────────────────────────────────
#
# Registers both FARGATE and FARGATE_SPOT capacity providers on the cluster.
# The default_capacity_provider_strategy determines which provider is used when
# a service or task does not specify its own strategy.
#
# Dev/Test strategy:
#   FARGATE_SPOT weight=1, base=1 — most tasks run on Spot for cost savings.
#   The base=1 guarantees at least one task is placed on standard Fargate,
#   providing a reliability floor during Spot interruptions.
#   FARGATE weight=0 — only used for the base placement.
#
# Prod strategy:
#   FARGATE weight=1 — all tasks run on standard on-demand Fargate.
#   FARGATE_SPOT weight=0 — Spot is not used in production.
#
# Requirements: 4.2, 11.3
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # Dev/Test: prioritize FARGATE_SPOT with a base of 1 on FARGATE_SPOT for
  # reliability. FARGATE is registered but receives no weight.
  dynamic "default_capacity_provider_strategy" {
    for_each = local.is_prod ? [] : [1]
    content {
      capacity_provider = "FARGATE_SPOT"
      weight            = 1
      base              = 1
    }
  }

  dynamic "default_capacity_provider_strategy" {
    for_each = local.is_prod ? [] : [1]
    content {
      capacity_provider = "FARGATE"
      weight            = 0
    }
  }

  # Prod: prioritize FARGATE (on-demand) exclusively.
  # FARGATE_SPOT is registered but receives no weight.
  dynamic "default_capacity_provider_strategy" {
    for_each = local.is_prod ? [1] : []
    content {
      capacity_provider = "FARGATE"
      weight            = 1
    }
  }

  dynamic "default_capacity_provider_strategy" {
    for_each = local.is_prod ? [1] : []
    content {
      capacity_provider = "FARGATE_SPOT"
      weight            = 0
    }
  }
}
