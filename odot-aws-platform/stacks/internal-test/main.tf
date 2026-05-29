# main.tf — Internal Test stack composition.
#
# Wires together the five platform modules (networking, ecs-cluster, security,
# monitoring, oidc) for the internal-test account-stage combination.
#
# Requirements: 1.1, 8.3

locals {
  account_type = "internal"
  stage        = "test"
}

# ── Networking ────────────────────────────────────────────────────────────────
#
# Provisions the internal-test VPC with private subnets only (no IGW, no public
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
# Provisions the ECS Fargate cluster with FARGATE_SPOT as the default capacity
# provider (test stage) and Container Insights enabled.
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  cluster_name = var.cluster_name
  stage        = local.stage
  tags         = var.tags
}

# ── Security ──────────────────────────────────────────────────────────────────
#
# Provisions account-wide security services: KMS CMK, GuardDuty, Security Hub,
# AWS Config, and Macie.
module "security" {
  source = "../../modules/security"

  account_type          = local.account_type
  account_id            = var.account_id
  org_id                = var.org_id
  config_s3_bucket_name = var.config_s3_bucket_name
  tags                  = var.tags
}

# ── Monitoring ────────────────────────────────────────────────────────────────
#
# Provisions CloudWatch dashboards, SNS topic, AWS Chatbot Slack integration,
# EventBridge rules for Security Hub findings, and AWS Budgets.
module "monitoring" {
  source = "../../modules/monitoring"

  account_type       = local.account_type
  stage              = local.stage
  slack_workspace_id = var.slack_workspace_id
  slack_channel_id   = var.slack_channel_id
  alert_email        = var.alert_email
  kms_key_arn        = module.security.kms_key_arn
  budget_limit_usd   = var.budget_limit_usd
  tags               = var.tags
}

# ── OIDC ──────────────────────────────────────────────────────────────────────
#
# Establishes the GitHub OIDC identity provider and IAM role for keyless
# CI/CD authentication from GitHub Actions.
module "oidc" {
  source = "../../modules/oidc"

  github_org   = var.github_org
  github_repos = var.github_repos
  account_id   = var.account_id
  account_type = local.account_type
  tags         = var.tags
}
