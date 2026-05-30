# main.tf — Internal Prod stack composition.
#
# In a shared-account testing setup, account-level singletons (OIDC, monitoring,
# security/KMS) are deployed once by the dev stack. This stack only deploys
# per-stage resources: networking and ECS cluster.
#
# In production (separate accounts per stage), all modules would be enabled.
#
# Requirements: 1.1, 8.3

locals {
  account_type = "internal"
  stage        = "prod"
}

# ── Networking ────────────────────────────────────────────────────────────────
#
# Provisions the internal-prod VPC with private subnets only (no IGW, no public
# subnets) across two Availability Zones.
module "networking" {
  source = "../../modules/networking"

  account_type       = local.account_type
  stage              = local.stage
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  tags               = var.tags
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────
#
# Provisions the ECS Fargate cluster with FARGATE as the primary capacity
# provider (prod stage) and Container Insights enabled.
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  cluster_name = var.cluster_name
  stage        = local.stage
  tags         = var.tags
}

# ── Security, Monitoring, OIDC ────────────────────────────────────────────────
#
# SKIPPED in shared-account testing. These are account-level singletons
# already deployed by the internal-dev stack:
#   - KMS key: alias/odot-internal
#   - SNS topic: odot-alerts-internal
#   - Chatbot: odot-chatbot-internal-dev
#   - OIDC provider + role: odot-github-actions-internal
#
# When migrating to separate accounts per stage, uncomment these modules.
