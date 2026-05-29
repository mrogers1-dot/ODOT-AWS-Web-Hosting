#!/usr/bin/env bash
# =============================================================================
# onboard-app.sh
#
# Automates the application onboarding process:
#   1. Creates a new repository from the odot-app-template
#   2. Configures Terraform variables
#   3. Sets GitHub repository variables for CI/CD
#   4. Creates protected branches (dev, test, prod)
#   5. Creates the production GitHub Environment
#
# Usage:
#   ./scripts/onboard-app.sh \
#     --app-name "fleet-tracker" \
#     --account-type "internal" \
#     --stage "dev" \
#     --github-org "ODOT-GitHub-Org"
#
# Prerequisites:
#   - GitHub CLI (gh) installed and authenticated
#   - Platform stacks deployed (run collect-stack-outputs.sh first)
#   - platform-outputs.json exists in the repo root
#   - jq installed
#
# Options:
#   --app-name        (required) Application name (lowercase, hyphens, 3-30 chars)
#   --account-type    (required) "internal" or "external"
#   --stage           (optional) Initial stage, default: "dev"
#   --github-org      (required) GitHub organization name
#   --container-port  (optional) Port the app listens on, default: 8080
#   --cpu             (optional) Fargate CPU units, default: 256
#   --memory          (optional) Fargate memory MiB, default: 512
#   --runtime         (optional) "linux" or "windows", default: "linux"
#   --outputs-file    (optional) Path to platform-outputs.json
#   --visibility      (optional) "internal" or "private", default: "internal"
#   --dry-run         (optional) Print what would be done without executing
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
STAGE="dev"
CONTAINER_PORT=8080
CPU=256
MEMORY=512
RUNTIME="linux"
VISIBILITY="internal"
DRY_RUN=false
OUTPUTS_FILE=""

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-name)       APP_NAME="$2"; shift 2 ;;
    --account-type)   ACCOUNT_TYPE="$2"; shift 2 ;;
    --stage)          STAGE="$2"; shift 2 ;;
    --github-org)     GITHUB_ORG="$2"; shift 2 ;;
    --container-port) CONTAINER_PORT="$2"; shift 2 ;;
    --cpu)            CPU="$2"; shift 2 ;;
    --memory)         MEMORY="$2"; shift 2 ;;
    --runtime)        RUNTIME="$2"; shift 2 ;;
    --outputs-file)   OUTPUTS_FILE="$2"; shift 2 ;;
    --visibility)     VISIBILITY="$2"; shift 2 ;;
    --dry-run)        DRY_RUN=true; shift ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate required arguments
# ---------------------------------------------------------------------------
if [[ -z "${APP_NAME:-}" ]]; then
  echo "ERROR: --app-name is required" >&2; exit 1
fi
if [[ -z "${ACCOUNT_TYPE:-}" ]]; then
  echo "ERROR: --account-type is required" >&2; exit 1
fi
if [[ -z "${GITHUB_ORG:-}" ]]; then
  echo "ERROR: --github-org is required" >&2; exit 1
fi

# Validate app_name format
if ! [[ "${APP_NAME}" =~ ^[a-z][a-z0-9-]{1,28}[a-z0-9]$ ]]; then
  echo "ERROR: app_name must be 3-30 chars, lowercase alphanumeric with hyphens, starting with a letter." >&2
  exit 1
fi

# Validate account_type
if [[ "${ACCOUNT_TYPE}" != "internal" && "${ACCOUNT_TYPE}" != "external" ]]; then
  echo "ERROR: --account-type must be 'internal' or 'external'" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -z "${OUTPUTS_FILE}" ]]; then
  OUTPUTS_FILE="${REPO_ROOT}/platform-outputs.json"
fi

# ---------------------------------------------------------------------------
# Check prerequisites
# ---------------------------------------------------------------------------
echo "==> Onboard Application: ${APP_NAME}"
echo "    Account type : ${ACCOUNT_TYPE}"
echo "    Stage        : ${STAGE}"
echo "    Organization : ${GITHUB_ORG}"
echo "    Runtime      : ${RUNTIME}"
echo "    Port         : ${CONTAINER_PORT}"
echo "    CPU/Memory   : ${CPU} / ${MEMORY}"
echo ""

# Check for required tools
for cmd in gh jq git; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "ERROR: '${cmd}' is required but not found in PATH." >&2
    exit 1
  fi
done

# Check gh auth
if ! gh auth status &>/dev/null; then
  echo "ERROR: GitHub CLI is not authenticated. Run 'gh auth login' first." >&2
  exit 1
fi

# Check outputs file
STACK_KEY="${ACCOUNT_TYPE}-${STAGE}"
if [[ -f "${OUTPUTS_FILE}" ]]; then
  echo "[OK] Platform outputs file found: ${OUTPUTS_FILE}"
else
  echo "WARNING: Platform outputs file not found at ${OUTPUTS_FILE}" >&2
  echo "         Infrastructure values will need to be set manually." >&2
  echo ""
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  echo ""
  echo "==> DRY RUN — no changes will be made"
  echo ""
fi

# ---------------------------------------------------------------------------
# Helper: run or print command
# ---------------------------------------------------------------------------
run() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "  [DRY RUN] $*"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# Step 1: Create repository from template
# ---------------------------------------------------------------------------
REPO_NAME="odot-${APP_NAME}"
FULL_REPO="${GITHUB_ORG}/${REPO_NAME}"

echo ""
echo "--- Step 1: Create repository from template ---"
echo "    Repository: ${FULL_REPO}"

if gh repo view "${FULL_REPO}" &>/dev/null; then
  echo "[SKIP] Repository ${FULL_REPO} already exists."
else
  run gh repo create "${FULL_REPO}" \
    --template "${GITHUB_ORG}/odot-app-template" \
    --${VISIBILITY} \
    --clone=false
  echo "[CREATED] ${FULL_REPO}"
fi

# ---------------------------------------------------------------------------
# Step 2: Clone and configure Terraform variables
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 2: Configure Terraform variables ---"

WORK_DIR="/tmp/onboard-${APP_NAME}"
if [[ "${DRY_RUN}" == "false" ]]; then
  rm -rf "${WORK_DIR}"
  gh repo clone "${FULL_REPO}" "${WORK_DIR}" -- --quiet
  cd "${WORK_DIR}"
else
  echo "  [DRY RUN] Would clone ${FULL_REPO} to ${WORK_DIR}"
fi

# Read platform outputs if available
VPC_ID=""
PRIVATE_SUBNET_IDS=""
ALB_SUBNET_IDS=""
CLUSTER_ARN=""
CLUSTER_NAME=""
KMS_KEY_ARN=""
SNS_TOPIC_ARN=""
WAF_ACL_ARN=""
DEPLOY_ROLE_ARN=""

if [[ -f "${OUTPUTS_FILE}" ]]; then
  VPC_ID=$(jq -r ".\"${STACK_KEY}\".vpc_id.value // empty" "${OUTPUTS_FILE}" 2>/dev/null || true)
  PRIVATE_SUBNET_IDS=$(jq -r ".\"${STACK_KEY}\".private_subnet_ids.value // [] | @json" "${OUTPUTS_FILE}" 2>/dev/null || true)
  ALB_SUBNET_IDS=$(jq -r ".\"${STACK_KEY}\".alb_subnet_ids.value // .\"${STACK_KEY}\".public_subnet_ids.value // [] | @json" "${OUTPUTS_FILE}" 2>/dev/null || true)
  CLUSTER_ARN=$(jq -r ".\"${STACK_KEY}\".cluster_arn.value // empty" "${OUTPUTS_FILE}" 2>/dev/null || true)
  CLUSTER_NAME=$(jq -r ".\"${STACK_KEY}\".cluster_name.value // empty" "${OUTPUTS_FILE}" 2>/dev/null || true)
  KMS_KEY_ARN=$(jq -r ".\"${STACK_KEY}\".kms_key_arn.value // empty" "${OUTPUTS_FILE}" 2>/dev/null || true)
  SNS_TOPIC_ARN=$(jq -r ".\"${STACK_KEY}\".sns_topic_arn.value // empty" "${OUTPUTS_FILE}" 2>/dev/null || true)
  WAF_ACL_ARN=$(jq -r ".\"${STACK_KEY}\".waf_acl_arn.value // empty" "${OUTPUTS_FILE}" 2>/dev/null || true)
  DEPLOY_ROLE_ARN=$(jq -r ".\"${STACK_KEY}\".github_actions_role_arn.value // empty" "${OUTPUTS_FILE}" 2>/dev/null || true)
fi

# Generate terraform.tfvars
if [[ "${DRY_RUN}" == "false" ]]; then
  cat > terraform/terraform.tfvars <<EOF
# Auto-generated by onboard-app.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Application: ${APP_NAME}

# Application Configuration
app_name       = "${APP_NAME}"
runtime        = "${RUNTIME}"
container_port = ${CONTAINER_PORT}
cpu            = ${CPU}
memory         = ${MEMORY}

# Infrastructure Configuration
aws_region         = "us-east-2"
account_type       = "${ACCOUNT_TYPE}"
stage              = "${STAGE}"
vpc_id             = "${VPC_ID:-vpc-PLACEHOLDER}"
private_subnet_ids = ${PRIVATE_SUBNET_IDS:-["subnet-PLACEHOLDER-1", "subnet-PLACEHOLDER-2"]}
alb_subnet_ids     = ${ALB_SUBNET_IDS:-["subnet-PLACEHOLDER-1", "subnet-PLACEHOLDER-2"]}
cluster_arn        = "${CLUSTER_ARN:-arn:aws:ecs:us-east-2:ACCOUNT_ID:cluster/WebHosting-Dev}"
cluster_name       = "${CLUSTER_NAME:-WebHosting-Dev}"
kms_key_arn        = "${KMS_KEY_ARN:-arn:aws:kms:us-east-2:ACCOUNT_ID:key/PLACEHOLDER}"
waf_acl_arn        = "${WAF_ACL_ARN:-}"
sns_topic_arn      = "${SNS_TOPIC_ARN:-arn:aws:sns:us-east-2:ACCOUNT_ID:odot-alerts-${ACCOUNT_TYPE}}"
owner              = "odot-platform-team"
EOF
  echo "[CREATED] terraform/terraform.tfvars"
else
  echo "  [DRY RUN] Would generate terraform/terraform.tfvars with app config"
fi

# ---------------------------------------------------------------------------
# Step 3: Set GitHub repository variables
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 3: Set GitHub repository variables ---"

ECR_REPO_NAME="odot-${APP_NAME}-${ACCOUNT_TYPE}"
ECS_SERVICE_NAME="${APP_NAME}-${STAGE}"

if [[ -n "${DEPLOY_ROLE_ARN}" ]]; then
  run gh variable set AWS_DEPLOY_ROLE_ARN --body "${DEPLOY_ROLE_ARN}" --repo "${FULL_REPO}"
  echo "    AWS_DEPLOY_ROLE_ARN = ${DEPLOY_ROLE_ARN}"
else
  echo "    [MANUAL] AWS_DEPLOY_ROLE_ARN — set after OIDC module is deployed"
fi

run gh variable set ECR_REPOSITORY_NAME --body "${ECR_REPO_NAME}" --repo "${FULL_REPO}"
echo "    ECR_REPOSITORY_NAME = ${ECR_REPO_NAME}"

run gh variable set ECS_CLUSTER_NAME --body "${CLUSTER_NAME:-WebHosting-Dev}" --repo "${FULL_REPO}"
echo "    ECS_CLUSTER_NAME = ${CLUSTER_NAME:-WebHosting-Dev}"

run gh variable set ECS_SERVICE_NAME --body "${ECS_SERVICE_NAME}" --repo "${FULL_REPO}"
echo "    ECS_SERVICE_NAME = ${ECS_SERVICE_NAME}"

# ---------------------------------------------------------------------------
# Step 4: Create branches
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 4: Create protected branches ---"

if [[ "${DRY_RUN}" == "false" ]]; then
  cd "${WORK_DIR}"

  # Commit the terraform.tfvars
  git add terraform/terraform.tfvars
  git commit -m "feat: configure ${APP_NAME} for ${ACCOUNT_TYPE}-${STAGE}" --quiet

  # Create and push branches
  for branch in dev test prod; do
    if git ls-remote --heads origin "${branch}" | grep -q "${branch}"; then
      echo "    [SKIP] Branch '${branch}' already exists"
    else
      git checkout -b "${branch}" --quiet 2>/dev/null || git checkout "${branch}" --quiet
      git push -u origin "${branch}" --quiet
      echo "    [CREATED] Branch '${branch}'"
      git checkout main --quiet 2>/dev/null || true
    fi
  done

  # Push main with the tfvars commit
  git checkout main --quiet 2>/dev/null || true
  git push origin main --quiet
else
  echo "  [DRY RUN] Would create and push branches: dev, test, prod"
fi

# ---------------------------------------------------------------------------
# Step 5: Create production environment
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 5: Create production environment ---"
echo "    NOTE: GitHub Environments with protection rules require manual setup."
echo "    Go to: https://github.com/${FULL_REPO}/settings/environments"
echo "    Create environment 'production' and add required reviewers."

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
if [[ "${DRY_RUN}" == "false" ]]; then
  rm -rf "${WORK_DIR}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "==> Onboarding complete for: ${APP_NAME}"
echo ""
echo "    Repository : https://github.com/${FULL_REPO}"
echo "    Next steps :"
echo "      1. Review terraform/terraform.tfvars (replace any PLACEHOLDER values)"
echo "      2. Run: cd terraform && terraform init && terraform apply"
echo "      3. Configure 'production' environment at:"
echo "         https://github.com/${FULL_REPO}/settings/environments"
echo "      4. Push application code to 'dev' branch to trigger first deployment"
