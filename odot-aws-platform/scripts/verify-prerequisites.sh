#!/usr/bin/env bash
# =============================================================================
# verify-prerequisites.sh
#
# Validates that all deployment prerequisites are in place before attempting
# a deployment. Checks local tools, AWS resources, and GitHub configuration.
#
# Usage:
#   ./scripts/verify-prerequisites.sh --app-name "fleet-tracker" \
#     --account-type "internal" --stage "dev" --github-org "ODOT-GitHub-Org"
#
# Options:
#   --app-name      (required) Application name
#   --account-type  (required) "internal" or "external"
#   --stage         (required) "dev", "test", or "prod"
#   --github-org    (required) GitHub organization name
#   --skip-aws      (optional) Skip AWS checks (useful without credentials)
#   --skip-github   (optional) Skip GitHub checks (useful without gh CLI)
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SKIP_AWS=false
SKIP_GITHUB=false

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-name)      APP_NAME="$2"; shift 2 ;;
    --account-type)  ACCOUNT_TYPE="$2"; shift 2 ;;
    --stage)         STAGE="$2"; shift 2 ;;
    --github-org)    GITHUB_ORG="$2"; shift 2 ;;
    --skip-aws)      SKIP_AWS=true; shift ;;
    --skip-github)   SKIP_GITHUB=true; shift ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${APP_NAME:-}" || -z "${ACCOUNT_TYPE:-}" || -z "${STAGE:-}" || -z "${GITHUB_ORG:-}" ]]; then
  echo "ERROR: --app-name, --account-type, --stage, and --github-org are all required." >&2
  exit 1
fi

REGION="us-east-2"
PASS=0
FAIL=0
WARN=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
check_pass() {
  echo "  ✅ $1"
  PASS=$((PASS + 1))
}

check_fail() {
  echo "  ❌ $1"
  FAIL=$((FAIL + 1))
}

check_warn() {
  echo "  ⚠️  $1"
  WARN=$((WARN + 1))
}

# ---------------------------------------------------------------------------
# Section 1: Local Tools
# ---------------------------------------------------------------------------
echo ""
echo "=== Local Tools ==="

for tool in terraform aws docker go git jq; do
  if command -v "${tool}" &>/dev/null; then
    VERSION=$("${tool}" --version 2>&1 | head -1)
    check_pass "${tool} installed (${VERSION})"
  else
    if [[ "${tool}" == "go" || "${tool}" == "jq" ]]; then
      check_warn "${tool} not found (optional for app deployment)"
    else
      check_fail "${tool} not found"
    fi
  fi
done

# Check gh CLI separately
if command -v gh &>/dev/null; then
  check_pass "gh CLI installed"
  if gh auth status &>/dev/null 2>&1; then
    check_pass "gh CLI authenticated"
  else
    check_fail "gh CLI not authenticated (run 'gh auth login')"
  fi
else
  if [[ "${SKIP_GITHUB}" == "true" ]]; then
    check_warn "gh CLI not found (GitHub checks skipped)"
  else
    check_fail "gh CLI not found"
  fi
fi

# ---------------------------------------------------------------------------
# Section 2: AWS Checks
# ---------------------------------------------------------------------------
echo ""
echo "=== AWS Resources ==="

if [[ "${SKIP_AWS}" == "true" ]]; then
  echo "  [SKIPPED] AWS checks disabled via --skip-aws"
else
  # Check AWS credentials
  if aws sts get-caller-identity &>/dev/null 2>&1; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
    check_pass "AWS credentials valid (account: ${ACCOUNT_ID})"
  else
    check_fail "AWS credentials not configured or expired"
    echo "         Run: aws sso login"
    SKIP_AWS=true
  fi

  if [[ "${SKIP_AWS}" == "false" ]]; then
    # Check ECS cluster
    CLUSTER_NAME="WebHosting-$(echo "${STAGE}" | sed 's/./\U&/')"
    if aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --region "${REGION}" \
        --query "clusters[0].status" --output text 2>/dev/null | grep -q "ACTIVE"; then
      check_pass "ECS cluster '${CLUSTER_NAME}' is ACTIVE"
    else
      check_fail "ECS cluster '${CLUSTER_NAME}' not found or not ACTIVE"
    fi

    # Check ECR repository
    ECR_REPO="odot-${APP_NAME}-${ACCOUNT_TYPE}"
    if aws ecr describe-repositories --repository-names "${ECR_REPO}" --region "${REGION}" &>/dev/null 2>&1; then
      check_pass "ECR repository '${ECR_REPO}' exists"
    else
      check_fail "ECR repository '${ECR_REPO}' not found (run terraform apply)"
    fi

    # Check OIDC role
    ROLE_NAME="odot-github-actions-${ACCOUNT_TYPE}"
    if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null 2>&1; then
      check_pass "IAM role '${ROLE_NAME}' exists"
    else
      check_fail "IAM role '${ROLE_NAME}' not found (deploy OIDC module)"
    fi

    # Check KMS key
    KMS_ALIAS="alias/odot-${ACCOUNT_TYPE}"
    if aws kms describe-key --key-id "${KMS_ALIAS}" --region "${REGION}" &>/dev/null 2>&1; then
      check_pass "KMS key '${KMS_ALIAS}' exists"
    else
      check_warn "KMS key '${KMS_ALIAS}' not found (may use different alias)"
    fi

    # Check SNS topic
    SNS_TOPIC="odot-alerts-${ACCOUNT_TYPE}"
    if aws sns list-topics --region "${REGION}" --query "Topics[?contains(TopicArn, '${SNS_TOPIC}')]" --output text 2>/dev/null | grep -q "${SNS_TOPIC}"; then
      check_pass "SNS topic '${SNS_TOPIC}' exists"
    else
      check_warn "SNS topic '${SNS_TOPIC}' not found"
    fi

    # Check Terraform state bucket
    BUCKET_PREFIX="odot-terraform-state-"
    if aws s3api list-buckets --query "Buckets[?starts_with(Name, '${BUCKET_PREFIX}')].Name" --output text 2>/dev/null | grep -q "${BUCKET_PREFIX}"; then
      check_pass "Terraform state bucket exists"
    else
      check_fail "Terraform state bucket not found (run bootstrap-backend.sh)"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Section 3: GitHub Checks
# ---------------------------------------------------------------------------
echo ""
echo "=== GitHub Configuration ==="

REPO_NAME="odot-${APP_NAME}"
FULL_REPO="${GITHUB_ORG}/${REPO_NAME}"

if [[ "${SKIP_GITHUB}" == "true" ]]; then
  echo "  [SKIPPED] GitHub checks disabled via --skip-github"
else
  # Check repository exists
  if gh repo view "${FULL_REPO}" &>/dev/null 2>&1; then
    check_pass "Repository '${FULL_REPO}' exists"
  else
    check_fail "Repository '${FULL_REPO}' not found"
  fi

  # Check repository variables
  for var_name in AWS_DEPLOY_ROLE_ARN ECR_REPOSITORY_NAME ECS_CLUSTER_NAME ECS_SERVICE_NAME; do
    VAR_VALUE=$(gh variable get "${var_name}" --repo "${FULL_REPO}" 2>/dev/null || true)
    if [[ -n "${VAR_VALUE}" ]]; then
      check_pass "Variable '${var_name}' is set"
    else
      check_fail "Variable '${var_name}' is not set"
    fi
  done

  # Check branches exist
  for branch in dev test prod; do
    if gh api "repos/${FULL_REPO}/branches/${branch}" &>/dev/null 2>&1; then
      check_pass "Branch '${branch}' exists"
    else
      check_fail "Branch '${branch}' not found"
    fi
  done

  # Check production environment
  if gh api "repos/${FULL_REPO}/environments/production" &>/dev/null 2>&1; then
    check_pass "Environment 'production' exists"
  else
    check_warn "Environment 'production' not configured (needed for prod deploys)"
  fi

  # Check Actions enabled
  if gh api "repos/${FULL_REPO}/actions/workflows" --jq '.total_count' 2>/dev/null | grep -qv "^0$"; then
    check_pass "GitHub Actions workflows found"
  else
    check_warn "No GitHub Actions workflows detected"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "==========================================="
echo "  Results: ✅ ${PASS} passed, ❌ ${FAIL} failed, ⚠️  ${WARN} warnings"
echo "==========================================="

if [[ ${FAIL} -gt 0 ]]; then
  echo ""
  echo "  Some checks failed. Resolve the issues above before deploying."
  exit 1
else
  echo ""
  echo "  All critical checks passed. Ready to deploy."
  exit 0
fi
