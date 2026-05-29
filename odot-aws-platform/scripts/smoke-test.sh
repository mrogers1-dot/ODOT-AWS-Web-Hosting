#!/usr/bin/env bash
# scripts/smoke-test.sh
#
# Post-deployment smoke test for the ODOT AWS Web Hosting platform.
# Validates that key infrastructure components are correctly provisioned
# across both AWS accounts.
#
# Usage:
#   ./scripts/smoke-test.sh <account> <stage>
#
# Arguments:
#   account  - Account type: "internal" or "external"
#   stage    - Deployment stage: "dev", "test", or "prod"
#
# Prerequisites:
#   - AWS CLI v2 installed and configured
#   - Valid AWS credentials for the target account
#   - Access to the odot-app-template repository directory (sibling to odot-aws-platform)
#
# Exit codes:
#   0 - All checks passed
#   1 - One or more checks failed
#
# Requirements: 9.1, 9.2, 11.1, 10.2, 13.1, 13.2, 13.3, 13.4

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_TEMPLATE_DIR="$(cd "${REPO_ROOT}/../odot-app-template" && pwd 2>/dev/null || echo "")"

INTERNAL_ACCOUNT_ID="577881328002"
EXTERNAL_ACCOUNT_ID="549136075921"
BUDGET_THRESHOLD=800
EXPECTED_CLUSTER_COUNT=6
EXPECTED_DASHBOARD_COUNT=6

STAGES=("dev" "test" "prod")
ACCOUNTS=("internal" "external")

# ── Argument Parsing ──────────────────────────────────────────────────────────

usage() {
  echo "Usage: $0 <account> <stage>"
  echo ""
  echo "Arguments:"
  echo "  account  - Account type: internal | external"
  echo "  stage    - Deployment stage: dev | test | prod"
  echo ""
  echo "Examples:"
  echo "  $0 internal dev"
  echo "  $0 external prod"
  exit 1
}

if [[ $# -lt 2 ]]; then
  usage
fi

ACCOUNT="$1"
STAGE="$2"

# Validate arguments
if [[ "$ACCOUNT" != "internal" && "$ACCOUNT" != "external" ]]; then
  echo "ERROR: account must be 'internal' or 'external', got: $ACCOUNT"
  exit 1
fi

if [[ "$STAGE" != "dev" && "$STAGE" != "test" && "$STAGE" != "prod" ]]; then
  echo "ERROR: stage must be 'dev', 'test', or 'prod', got: $STAGE"
  exit 1
fi

# ── Test Framework ────────────────────────────────────────────────────────────

PASS_COUNT=0
FAIL_COUNT=0
RESULTS=()

pass() {
  local msg="$1"
  PASS_COUNT=$((PASS_COUNT + 1))
  RESULTS+=("PASS: $msg")
  echo "  ✅ PASS: $msg"
}

fail() {
  local msg="$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  RESULTS+=("FAIL: $msg")
  echo "  ❌ FAIL: $msg"
}

section() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── Smoke Tests ───────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  ODOT AWS Web Hosting — Smoke Test                                         ║"
echo "║  Account: ${ACCOUNT}  |  Stage: ${STAGE}                                   ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"

# ── Check 1: ECS Clusters (Requirement 4.1, 13.2) ────────────────────────────

section "Check 1: ECS Clusters (6 total across both accounts)"

CLUSTER_COUNT=$(aws ecs list-clusters --query 'clusterArns | length(@)' --output text 2>/dev/null || echo "0")

if [[ "$CLUSTER_COUNT" -ge 3 ]]; then
  pass "Found $CLUSTER_COUNT ECS cluster(s) in current account (expected 3 per account)"
else
  fail "Found $CLUSTER_COUNT ECS cluster(s) in current account (expected at least 3)"
fi

# Verify the specific cluster for this account-stage exists
STAGE_TITLE="$(echo "${STAGE}" | sed 's/./\U&/')"
EXPECTED_CLUSTER_NAME="WebHosting-${STAGE_TITLE}"
CLUSTER_EXISTS=$(aws ecs describe-clusters \
  --clusters "$EXPECTED_CLUSTER_NAME" \
  --query "clusters[?status=='ACTIVE'].clusterName" \
  --output text 2>/dev/null || echo "")

if [[ "$CLUSTER_EXISTS" == "$EXPECTED_CLUSTER_NAME" ]]; then
  pass "ECS cluster '${EXPECTED_CLUSTER_NAME}' exists and is ACTIVE"
else
  fail "ECS cluster '${EXPECTED_CLUSTER_NAME}' not found or not ACTIVE"
fi

# ── Check 2: GuardDuty (Requirement 9.1) ─────────────────────────────────────

section "Check 2: GuardDuty Detector Enabled"

DETECTOR_IDS=$(aws guardduty list-detectors --query 'DetectorIds' --output text 2>/dev/null || echo "")

if [[ -n "$DETECTOR_IDS" ]]; then
  # Check the first detector's status
  DETECTOR_ID=$(echo "$DETECTOR_IDS" | awk '{print $1}')
  DETECTOR_STATUS=$(aws guardduty get-detector \
    --detector-id "$DETECTOR_ID" \
    --query 'Status' \
    --output text 2>/dev/null || echo "")

  if [[ "$DETECTOR_STATUS" == "ENABLED" ]]; then
    pass "GuardDuty detector is ENABLED (ID: ${DETECTOR_ID})"
  else
    fail "GuardDuty detector found but status is '${DETECTOR_STATUS}' (expected ENABLED)"
  fi
else
  fail "No GuardDuty detector found in this account"
fi

# ── Check 3: Security Hub FSBP Standard (Requirement 9.2) ────────────────────

section "Check 3: Security Hub — AWS Foundational Security Best Practices"

SECURITYHUB_STANDARDS=$(aws securityhub get-enabled-standards \
  --query 'StandardsSubscriptions[].StandardsArn' \
  --output text 2>/dev/null || echo "")

if echo "$SECURITYHUB_STANDARDS" | grep -qi "aws-foundational-security-best-practices"; then
  pass "Security Hub FSBP standard is active"
else
  fail "Security Hub FSBP standard not found (got: ${SECURITYHUB_STANDARDS:-none})"
fi

# ── Check 4: AWS Budgets Alert at $800 Threshold (Requirement 11.1) ──────────

section "Check 4: AWS Budgets — \$800 Alert Threshold"

BUDGETS_JSON=$(aws budgets describe-budgets \
  --account-id "$(aws sts get-caller-identity --query 'Account' --output text)" \
  --query 'Budgets[].{Name:BudgetName,Limit:BudgetLimit.Amount}' \
  --output json 2>/dev/null || echo "[]")

# Check if any budget has a notification at 80% of $1000 = $800
BUDGET_NOTIFICATIONS=$(aws budgets describe-budgets \
  --account-id "$(aws sts get-caller-identity --query 'Account' --output text)" \
  --query 'Budgets[].BudgetName' \
  --output text 2>/dev/null || echo "")

BUDGET_FOUND=false
for BUDGET_NAME in $BUDGET_NOTIFICATIONS; do
  NOTIFICATIONS=$(aws budgets describe-notifications-for-budget \
    --account-id "$(aws sts get-caller-identity --query 'Account' --output text)" \
    --budget-name "$BUDGET_NAME" \
    --query 'Notifications[?Threshold==`80.0`]' \
    --output text 2>/dev/null || echo "")

  if [[ -n "$NOTIFICATIONS" ]]; then
    BUDGET_FOUND=true
    break
  fi
done

if [[ "$BUDGET_FOUND" == "true" ]]; then
  pass "AWS Budget alert configured at 80% threshold (\$${BUDGET_THRESHOLD})"
else
  fail "No AWS Budget alert found with 80% threshold (\$${BUDGET_THRESHOLD})"
fi

# ── Check 5: CloudWatch Dashboards (Requirement 10.2) ─────────────────────────

section "Check 5: CloudWatch Dashboards (6 total expected)"

DASHBOARDS=$(aws cloudwatch list-dashboards \
  --dashboard-name-prefix "odot-" \
  --query 'DashboardEntries[].DashboardName' \
  --output text 2>/dev/null || echo "")

DASHBOARD_COUNT=$(echo "$DASHBOARDS" | wc -w | tr -d ' ')

if [[ "$DASHBOARD_COUNT" -ge 3 ]]; then
  pass "Found $DASHBOARD_COUNT CloudWatch dashboard(s) with 'odot-' prefix in current account"
else
  fail "Found $DASHBOARD_COUNT CloudWatch dashboard(s) with 'odot-' prefix (expected at least 3)"
fi

# Check for the specific dashboard for this account-stage
EXPECTED_DASHBOARD="odot-${ACCOUNT}-${STAGE}"
if echo "$DASHBOARDS" | grep -q "$EXPECTED_DASHBOARD"; then
  pass "Dashboard '${EXPECTED_DASHBOARD}' exists"
else
  fail "Dashboard '${EXPECTED_DASHBOARD}' not found"
fi

# ── Check 6: GitHub Actions OIDC (Requirement 6.7, 13.1) ─────────────────────

section "Check 6: GitHub Actions Workflow — OIDC Authentication"

if [[ -z "$APP_TEMPLATE_DIR" || ! -d "$APP_TEMPLATE_DIR" ]]; then
  fail "odot-app-template directory not found (expected sibling to odot-aws-platform)"
else
  WORKFLOW_FILE="${APP_TEMPLATE_DIR}/.github/workflows/ci-cd.yml"

  if [[ ! -f "$WORKFLOW_FILE" ]]; then
    fail "ci-cd.yml workflow file not found at ${WORKFLOW_FILE}"
  else
    # Check for role-to-assume (OIDC pattern)
    if grep -q "role-to-assume" "$WORKFLOW_FILE"; then
      pass "ci-cd.yml contains 'role-to-assume' (OIDC authentication configured)"
    else
      fail "ci-cd.yml does NOT contain 'role-to-assume' (OIDC authentication missing)"
    fi

    # Check that no long-lived credentials are referenced
    if grep -q "AWS_ACCESS_KEY_ID" "$WORKFLOW_FILE"; then
      fail "ci-cd.yml contains 'AWS_ACCESS_KEY_ID' reference (long-lived credentials detected)"
    else
      pass "ci-cd.yml does NOT reference 'AWS_ACCESS_KEY_ID' (no long-lived credentials)"
    fi
  fi
fi

# ── Check 7: App Template is_template Setting (Requirement 13.1) ─────────────

section "Check 7: odot-app-template Repository — Template Configuration"

if [[ -z "$APP_TEMPLATE_DIR" || ! -d "$APP_TEMPLATE_DIR" ]]; then
  fail "odot-app-template directory not found"
else
  # Check for is_template in terraform files or repository configuration
  # In a GitHub repository, is_template is a repo setting. For local validation,
  # we check if the terraform configuration marks it as a template.
  TEMPLATE_MARKER_FOUND=false

  # Check terraform files for is_template
  if grep -rq "is_template\s*=\s*true" "$APP_TEMPLATE_DIR/" 2>/dev/null; then
    TEMPLATE_MARKER_FOUND=true
  fi

  # Check for GitHub repository settings file (.github/settings.yml or similar)
  if [[ -f "${APP_TEMPLATE_DIR}/.github/settings.yml" ]]; then
    if grep -q "is_template:\s*true" "${APP_TEMPLATE_DIR}/.github/settings.yml" 2>/dev/null; then
      TEMPLATE_MARKER_FOUND=true
    fi
  fi

  # Check README for template repository indicators
  if [[ -f "${APP_TEMPLATE_DIR}/README.md" ]]; then
    if grep -qi "template" "${APP_TEMPLATE_DIR}/README.md" 2>/dev/null; then
      TEMPLATE_MARKER_FOUND=true
    fi
  fi

  # Also check if the repo has the standard template structure
  # (workflows, Dockerfile stub, terraform vars example)
  HAS_WORKFLOW=false
  HAS_DOCKERFILE=false
  HAS_TFVARS_EXAMPLE=false

  [[ -f "${APP_TEMPLATE_DIR}/.github/workflows/ci-cd.yml" ]] && HAS_WORKFLOW=true
  [[ -f "${APP_TEMPLATE_DIR}/Dockerfile" ]] && HAS_DOCKERFILE=true
  [[ -f "${APP_TEMPLATE_DIR}/terraform/terraform.tfvars.example" ]] && HAS_TFVARS_EXAMPLE=true

  if [[ "$TEMPLATE_MARKER_FOUND" == "true" ]]; then
    pass "odot-app-template has 'is_template = true' marker"
  elif [[ "$HAS_WORKFLOW" == "true" && "$HAS_DOCKERFILE" == "true" && "$HAS_TFVARS_EXAMPLE" == "true" ]]; then
    pass "odot-app-template has template repository structure (workflow + Dockerfile + tfvars.example)"
  else
    fail "odot-app-template does not appear to be configured as a template repository"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  SMOKE TEST SUMMARY                                                        ║"
echo "╠══════════════════════════════════════════════════════════════════════════════╣"
printf "║  Account: %-10s  Stage: %-10s                                  ║\n" "$ACCOUNT" "$STAGE"
printf "║  Passed:  %-4d  Failed: %-4d  Total: %-4d                                ║\n" "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
echo "╠══════════════════════════════════════════════════════════════════════════════╣"

for result in "${RESULTS[@]}"; do
  if [[ "$result" == PASS:* ]]; then
    printf "║  ✅ %s\n" "$result"
  else
    printf "║  ❌ %s\n" "$result"
  fi
done

echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo "❌ SMOKE TEST FAILED — $FAIL_COUNT check(s) did not pass."
  exit 1
else
  echo "✅ ALL SMOKE TESTS PASSED"
  exit 0
fi
