# modules/oidc/main.tf
#
# Establishes the GitHub OIDC identity provider and a least-privilege IAM role
# for GitHub Actions CI/CD pipelines. No long-lived AWS credentials are stored
# in GitHub — authentication is entirely keyless via OIDC federation.
#
# Requirements: 6.7, 9.6, 13.1

locals {
  # Merge caller-supplied tags with the module-level defaults so that every
  # resource always carries the three mandatory tags (Environment, Project, Owner).
  default_tags = {
    Project = "ODOTWebHosting"
    Owner   = "odot-platform-team"
  }
  merged_tags = merge(local.default_tags, var.tags)

  # GitHub OIDC issuer URL — used as the provider URL and in trust-policy conditions.
  github_oidc_url = "https://token.actions.githubusercontent.com"

  # Build the list of allowed sub-claim patterns, one per repo.
  # Pattern: repo:{org}/{repo}:*  — scopes trust to a specific repository only.
  # Using StringLike (not StringEquals) to allow branch/environment/tag suffixes.
  allowed_subjects = [
    for repo in var.github_repos :
    "repo:${var.github_org}/${repo}:*"
  ]
}

# ── GitHub OIDC Identity Provider ────────────────────────────────────────────
#
# The thumbprint below is the SHA-1 fingerprint of the GitHub Actions OIDC
# certificate root CA as published by GitHub:
# https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
#
# Audience is set to sts.amazonaws.com per AWS documentation for OIDC federation.
resource "aws_iam_openid_connect_provider" "github" {
  url = local.github_oidc_url

  # sts.amazonaws.com is the required audience for AWS STS OIDC federation.
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC root CA thumbprint — update if GitHub rotates their certificate.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = local.merged_tags
}

# ── Trust Policy ─────────────────────────────────────────────────────────────
#
# Allows GitHub Actions to assume this role via OIDC, but ONLY for workflows
# running in the explicitly listed repositories. The StringLike condition on
# the sub claim prevents any other GitHub org or repo from assuming the role.
data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    sid     = "AllowGitHubOIDCFederation"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # StringLike is intentional: the sub claim includes a suffix after the repo
    # name (e.g., ":ref:refs/heads/main") so an exact match would never work.
    # The wildcard is constrained to a specific org/repo prefix, not a global *.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.allowed_subjects
    }
  }
}

# ── IAM Role ─────────────────────────────────────────────────────────────────
#
# Named odot-github-actions-{account_type} per the design naming convention.
# This role is assumed by GitHub Actions jobs that need to push images to ECR
# and deploy to ECS. It carries no console access and no long-lived credentials.
resource "aws_iam_role" "github_actions" {
  name               = "odot-github-actions-${var.account_type}"
  description        = "Assumed by GitHub Actions via OIDC for ECR push and ECS deploy in the ${var.account_type} account"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json

  # Limit the maximum session duration to 1 hour — sufficient for a full
  # build-scan-deploy cycle (Requirement 6.9: pipeline completes in < 15 min).
  max_session_duration = 3600

  tags = local.merged_tags
}

# ── Least-Privilege Inline Policy ────────────────────────────────────────────
#
# Grants only the permissions required for the CI/CD pipeline stages:
#   - ECR: authenticate, check layers, push image
#   - ECS: register new task definition, update service, describe services
#   - IAM PassRole: scoped to ECS task execution roles ONLY (not *)
#
# iam:PassRole is restricted to the ARN pattern for ECS task execution roles
# (odot-ecs-task-*) to prevent privilege escalation via arbitrary role passing.
data "aws_iam_policy_document" "github_actions_permissions" {
  # ECR authentication — GetAuthorizationToken has no resource-level restriction.
  statement {
    sid    = "ECRAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  # ECR image operations — scoped to repositories in this account.
  statement {
    sid    = "ECRImageOps"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = ["arn:aws:ecr:*:${var.account_id}:repository/*"]
  }

  # ECS deployment operations — scoped to this account.
  statement {
    sid    = "ECSDeployOps"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
    ]
    resources = ["*"]
  }

  # iam:PassRole — MUST be scoped to ECS task execution roles only.
  # The ARN pattern arn:aws:iam::*:role/odot-ecs-task-* matches only roles
  # following the naming convention defined in the design (odot-ecs-task-{app}-{stage}).
  # This prevents the pipeline from passing arbitrary roles to ECS.
  statement {
    sid    = "PassRoleToECSTaskExecutionRolesOnly"
    effect = "Allow"
    actions = [
      "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::${var.account_id}:role/odot-ecs-task-*",
    ]

    # Additional condition: PassRole is only valid when the receiving service
    # is ECS (prevents passing the role to other AWS services).
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "odot-github-actions-${var.account_type}-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}
