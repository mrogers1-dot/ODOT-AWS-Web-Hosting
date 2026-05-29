#!/usr/bin/env bash
# =============================================================================
# collect-stack-outputs.sh
#
# Collects Terraform outputs from all deployed stacks and writes them to a
# single JSON file. Application teams use these values to configure their
# terraform.tfvars and GitHub repository variables.
#
# Usage:
#   ./scripts/collect-stack-outputs.sh [output-file]
#
#   Default output file: ./platform-outputs.json
#
# Prerequisites:
#   - Terraform installed
#   - All stacks have been deployed (terraform apply)
#   - AWS credentials configured for the target accounts
#
# Output format:
#   {
#     "internal-dev": { "vpc_id": "...", "cluster_arn": "...", ... },
#     "internal-test": { ... },
#     ...
#   }
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STACKS_DIR="${REPO_ROOT}/stacks"
OUTPUT_FILE="${1:-${REPO_ROOT}/platform-outputs.json}"

STACKS=(
  "internal-dev"
  "internal-test"
  "internal-prod"
  "external-dev"
  "external-test"
  "external-prod"
)

echo "==> Collecting Terraform outputs from all stacks"
echo "    Stacks dir : ${STACKS_DIR}"
echo "    Output file: ${OUTPUT_FILE}"
echo ""

# Start JSON object
echo "{" > "${OUTPUT_FILE}"

FIRST=true
for stack in "${STACKS[@]}"; do
  STACK_DIR="${STACKS_DIR}/${stack}"

  if [[ ! -d "${STACK_DIR}" ]]; then
    echo "[SKIP] ${stack} — directory not found"
    continue
  fi

  echo -n "[COLLECT] ${stack} ... "

  # Try to get outputs; skip if stack hasn't been initialized/applied
  if OUTPUTS=$(cd "${STACK_DIR}" && terraform output -json 2>/dev/null); then
    if [[ "${FIRST}" == "true" ]]; then
      FIRST=false
    else
      echo "," >> "${OUTPUT_FILE}"
    fi
    echo "  \"${stack}\": ${OUTPUTS}" >> "${OUTPUT_FILE}"
    echo "OK"
  else
    echo "SKIPPED (not initialized or no outputs)"
  fi
done

echo "" >> "${OUTPUT_FILE}"
echo "}" >> "${OUTPUT_FILE}"

echo ""
echo "==> Done. Outputs written to: ${OUTPUT_FILE}"
echo ""
echo "    Use these values to populate application terraform.tfvars files."
echo "    Example: jq '.\"internal-dev\".vpc_id.value' ${OUTPUT_FILE}"
