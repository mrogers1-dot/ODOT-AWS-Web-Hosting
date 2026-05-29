#!/usr/bin/env bash
# =============================================================================
# configure-backend.sh
#
# Replaces the MGMT_ACCOUNT_ID placeholder in all backend.tf files across the
# platform repository. Supports split-account state storage:
#   - Internal stacks → state in the Internal account
#   - External stacks → state in the External account
#
# Usage:
#   # Split-account mode (recommended):
#   ./scripts/configure-backend.sh --internal 577881328002 --external 549136075921
#
#   # Single-account mode (all state in one bucket):
#   ./scripts/configure-backend.sh <ACCOUNT_ID>
#
# What it does:
#   - Finds all backend.tf files in the repository
#   - Replaces "MGMT_ACCOUNT_ID" with the appropriate account ID
#   - Internal/root backend.tf files get the internal account ID
#   - External backend.tf files get the external account ID
#   - Reports which files were updated
#
# Idempotency:
#   Safe to re-run. If the placeholder has already been replaced, no changes
#   are made to those files.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
INTERNAL_ACCOUNT_ID=""
EXTERNAL_ACCOUNT_ID=""
SINGLE_ACCOUNT_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --internal)
      INTERNAL_ACCOUNT_ID="$2"
      shift 2
      ;;
    --external)
      EXTERNAL_ACCOUNT_ID="$2"
      shift 2
      ;;
    *)
      # Legacy single-account mode
      SINGLE_ACCOUNT_ID="$1"
      shift
      ;;
  esac
done

# If single-account mode, use it for both
if [[ -n "${SINGLE_ACCOUNT_ID}" ]]; then
  INTERNAL_ACCOUNT_ID="${SINGLE_ACCOUNT_ID}"
  EXTERNAL_ACCOUNT_ID="${SINGLE_ACCOUNT_ID}"
fi

# Fall back to environment variable
INTERNAL_ACCOUNT_ID="${INTERNAL_ACCOUNT_ID:-${AWS_ACCOUNT_ID:-}}"
EXTERNAL_ACCOUNT_ID="${EXTERNAL_ACCOUNT_ID:-${AWS_ACCOUNT_ID:-}}"

if [[ -z "${INTERNAL_ACCOUNT_ID}" || -z "${EXTERNAL_ACCOUNT_ID}" ]]; then
  echo "ERROR: Account IDs are required." >&2
  echo "" >&2
  echo "  Split-account mode:" >&2
  echo "    $0 --internal <INTERNAL_ACCOUNT_ID> --external <EXTERNAL_ACCOUNT_ID>" >&2
  echo "" >&2
  echo "  Single-account mode:" >&2
  echo "    $0 <ACCOUNT_ID>" >&2
  exit 1
fi

# Validate account ID format (12 digits)
if ! [[ "${INTERNAL_ACCOUNT_ID}" =~ ^[0-9]{12}$ ]]; then
  echo "ERROR: Internal account ID must be exactly 12 digits. Got: '${INTERNAL_ACCOUNT_ID}'" >&2
  exit 1
fi

if ! [[ "${EXTERNAL_ACCOUNT_ID}" =~ ^[0-9]{12}$ ]]; then
  echo "ERROR: External account ID must be exactly 12 digits. Got: '${EXTERNAL_ACCOUNT_ID}'" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Configure backend.tf files"
echo "    Internal Account ID : ${INTERNAL_ACCOUNT_ID}"
echo "    External Account ID : ${EXTERNAL_ACCOUNT_ID}"
echo "    Repository          : ${REPO_ROOT}"
echo ""

UPDATED=0
SKIPPED=0

while IFS= read -r -d '' file; do
  if grep -q "MGMT_ACCOUNT_ID" "${file}"; then
    # Determine which account ID to use based on file path
    if [[ "${file}" == *"/external-"* ]]; then
      ACCOUNT_ID="${EXTERNAL_ACCOUNT_ID}"
    else
      ACCOUNT_ID="${INTERNAL_ACCOUNT_ID}"
    fi

    sed -i '' "s/MGMT_ACCOUNT_ID/${ACCOUNT_ID}/g" "${file}" 2>/dev/null || \
    sed -i "s/MGMT_ACCOUNT_ID/${ACCOUNT_ID}/g" "${file}"
    echo "[UPDATED] ${file#${REPO_ROOT}/} → account ${ACCOUNT_ID}"
    UPDATED=$((UPDATED + 1))
  else
    echo "[SKIP]    ${file#${REPO_ROOT}/} (already configured)"
    SKIPPED=$((SKIPPED + 1))
  fi
done < <(find "${REPO_ROOT}" -name "backend.tf" -print0)

echo ""
echo "==> Done. Updated: ${UPDATED}, Skipped: ${SKIPPED}"
