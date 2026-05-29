#!/usr/bin/env bash
# =============================================================================
# deploy-platform.sh
#
# Deploys all platform stacks in the correct dependency order. Optionally
# targets a single stack or a subset of stacks.
#
# Usage:
#   ./scripts/deploy-platform.sh                    # Deploy all stacks
#   ./scripts/deploy-platform.sh internal-dev       # Deploy one stack
#   ./scripts/deploy-platform.sh internal           # Deploy all internal stacks
#   ./scripts/deploy-platform.sh --plan-only        # Plan all stacks without applying
#
# Options:
#   --plan-only    Run terraform plan only (no apply)
#   --auto-approve Skip interactive approval (use in CI only)
#
# Deployment order:
#   1. internal-dev → internal-test → internal-prod
#   2. external-dev → external-test → external-prod
#
# Prerequisites:
#   - Terraform installed (>= 1.5)
#   - AWS credentials configured for target accounts
#   - Backend bootstrapped (run bootstrap-backend.sh first)
#   - backend.tf files configured (run configure-backend.sh first)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STACKS_DIR="${REPO_ROOT}/stacks"

# Ordered list of all stacks
ALL_STACKS=(
  "internal-dev"
  "internal-test"
  "internal-prod"
  "external-dev"
  "external-test"
  "external-prod"
)

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
PLAN_ONLY=false
AUTO_APPROVE=false
TARGET_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan-only)     PLAN_ONLY=true; shift ;;
    --auto-approve)  AUTO_APPROVE=true; shift ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2
      exit 1
      ;;
    *)
      TARGET_FILTER="$1"; shift ;;
  esac
done

# ---------------------------------------------------------------------------
# Determine which stacks to deploy
# ---------------------------------------------------------------------------
STACKS_TO_DEPLOY=()

if [[ -z "${TARGET_FILTER}" ]]; then
  STACKS_TO_DEPLOY=("${ALL_STACKS[@]}")
else
  for stack in "${ALL_STACKS[@]}"; do
    if [[ "${stack}" == "${TARGET_FILTER}" || "${stack}" == ${TARGET_FILTER}* ]]; then
      STACKS_TO_DEPLOY+=("${stack}")
    fi
  done

  if [[ ${#STACKS_TO_DEPLOY[@]} -eq 0 ]]; then
    echo "ERROR: No stacks match filter '${TARGET_FILTER}'" >&2
    echo "  Available stacks: ${ALL_STACKS[*]}" >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------
echo "==> Platform Deployment"
echo "    Mode   : $(if ${PLAN_ONLY}; then echo "PLAN ONLY"; else echo "APPLY"; fi)"
echo "    Stacks : ${STACKS_TO_DEPLOY[*]}"
echo ""

SUCCEEDED=()
FAILED=()

for stack in "${STACKS_TO_DEPLOY[@]}"; do
  STACK_DIR="${STACKS_DIR}/${stack}"

  if [[ ! -d "${STACK_DIR}" ]]; then
    echo "[SKIP] ${stack} — directory not found at ${STACK_DIR}"
    continue
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Stack: ${stack}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  cd "${STACK_DIR}"

  # Init
  echo "[INIT] terraform init ..."
  if ! terraform init -input=false -no-color 2>&1 | tail -3; then
    echo "[FAIL] terraform init failed for ${stack}"
    FAILED+=("${stack}")
    continue
  fi

  # Plan
  echo "[PLAN] terraform plan ..."
  if ! terraform plan -input=false -no-color -out=tfplan 2>&1 | tail -5; then
    echo "[FAIL] terraform plan failed for ${stack}"
    FAILED+=("${stack}")
    continue
  fi

  # Apply (unless plan-only)
  if [[ "${PLAN_ONLY}" == "true" ]]; then
    echo "[DONE] Plan complete for ${stack} (--plan-only mode)"
    SUCCEEDED+=("${stack}")
    rm -f tfplan
  else
    echo "[APPLY] terraform apply ..."
    APPLY_ARGS=(-input=false -no-color tfplan)

    if terraform apply "${APPLY_ARGS[@]}" 2>&1 | tail -5; then
      echo "[DONE] ${stack} deployed successfully"
      SUCCEEDED+=("${stack}")
    else
      echo "[FAIL] terraform apply failed for ${stack}"
      FAILED+=("${stack}")
    fi
    rm -f tfplan
  fi

  echo ""
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "==========================================="
echo "  Deployment Summary"
echo "==========================================="
echo "  Succeeded: ${#SUCCEEDED[@]} — ${SUCCEEDED[*]:-none}"
echo "  Failed:    ${#FAILED[@]} — ${FAILED[*]:-none}"
echo "==========================================="

if [[ ${#FAILED[@]} -gt 0 ]]; then
  exit 1
fi
