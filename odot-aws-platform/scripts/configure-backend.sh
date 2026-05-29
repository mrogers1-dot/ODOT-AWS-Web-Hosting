#!/usr/bin/env bash
# =============================================================================
# configure-backend.sh
#
# Replaces the MGMT_ACCOUNT_ID placeholder in all backend.tf files across the
# platform repository. Run this after bootstrap-backend.sh to make all stacks
# point to the correct S3 state bucket.
#
# Usage:
#   ./scripts/configure-backend.sh <MGMT_ACCOUNT_ID>
#
# What it does:
#   - Finds all backend.tf files in the repository
#   - Replaces "MGMT_ACCOUNT_ID" with the provided account ID
#   - Reports which files were updated
#
# Idempotency:
#   Safe to re-run. If the placeholder has already been replaced, no changes
#   are made to those files.
# =============================================================================

set -euo pipefail

MGMT_ACCOUNT_ID="${1:-${AWS_ACCOUNT_ID:-}}"

if [[ -z "${MGMT_ACCOUNT_ID}" ]]; then
  echo "ERROR: Management account ID is required." >&2
  echo "  Usage: $0 <MGMT_ACCOUNT_ID>" >&2
  exit 1
fi

# Validate account ID format (12 digits)
if ! [[ "${MGMT_ACCOUNT_ID}" =~ ^[0-9]{12}$ ]]; then
  echo "ERROR: Account ID must be exactly 12 digits. Got: '${MGMT_ACCOUNT_ID}'" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Configure backend.tf files"
echo "    Account ID : ${MGMT_ACCOUNT_ID}"
echo "    Repository : ${REPO_ROOT}"
echo ""

UPDATED=0
SKIPPED=0

while IFS= read -r -d '' file; do
  if grep -q "MGMT_ACCOUNT_ID" "${file}"; then
    sed -i '' "s/MGMT_ACCOUNT_ID/${MGMT_ACCOUNT_ID}/g" "${file}" 2>/dev/null || \
    sed -i "s/MGMT_ACCOUNT_ID/${MGMT_ACCOUNT_ID}/g" "${file}"
    echo "[UPDATED] ${file#${REPO_ROOT}/}"
    UPDATED=$((UPDATED + 1))
  else
    echo "[SKIP]    ${file#${REPO_ROOT}/} (already configured)"
    SKIPPED=$((SKIPPED + 1))
  fi
done < <(find "${REPO_ROOT}" -name "backend.tf" -print0)

echo ""
echo "==> Done. Updated: ${UPDATED}, Skipped: ${SKIPPED}"
