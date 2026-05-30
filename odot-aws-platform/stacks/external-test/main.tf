# main.tf — External Test stack composition.
#
# In a shared-account testing setup, account-level singletons (OIDC, monitoring,
# security/KMS) are deployed once by the dev stack. This stack only deploys
# per-stage resources: networking and ECS cluster.
#
# In production (separate accounts per stage), all modules would be enabled.
#
# Requirements: 1.1, 3.3, 8.3

locals {
  account_type = "external"
  stage        = "test"
}

# ── Networking ────────────────────────────────────────────────────────────────
#
# Provisions the external-test VPC with public subnets (IGW-attached) and
# private subnets (NAT gateway for egress) across two Availability Zones.
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
# Provisions the ECS Fargate cluster with FARGATE_SPOT as the default capacity
# provider (test stage) and Container Insights enabled.
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  cluster_name = var.cluster_name
  stage        = local.stage
  tags         = var.tags
}

# ── Security, Monitoring, OIDC ────────────────────────────────────────────────
#
# SKIPPED in shared-account testing. These are account-level singletons
# already deployed by the external-dev stack:
#   - KMS key: alias/odot-external
#   - SNS topic: odot-alerts-external
#   - Chatbot: odot-chatbot-external-dev
#   - OIDC provider + role: odot-github-actions-external
#
# When migrating to separate accounts per stage, uncomment these modules.
