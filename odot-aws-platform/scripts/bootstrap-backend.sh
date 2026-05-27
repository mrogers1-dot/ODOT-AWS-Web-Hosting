#!/usr/bin/env bash
# =============================================================================
# bootstrap-backend.sh
#
# Creates the Terraform remote state backend resources in the management account:
#   - S3 bucket:       odot-terraform-state-${MGMT_ACCOUNT_ID}
#   - DynamoDB table:  odot-terraform-locks
#
# Usage:
#   ./scripts/bootstrap-backend.sh <MGMT_ACCOUNT_ID>
#
#   Or set the AWS_ACCOUNT_ID environment variable and run without arguments:
#   AWS_ACCOUNT_ID=123456789012 ./scripts/bootstrap-backend.sh
#
# Prerequisites:
#   - AWS CLI v2 installed and on PATH
#   - Active AWS credentials with permissions to create S3 buckets,
#     enable versioning/encryption, block public access, and create
#     DynamoDB tables in the management account.
#
# Idempotency:
#   The script checks whether each resource already exists before creating it.
#   Re-running the script against an already-bootstrapped account is safe.
#
# Region:
#   All resources are created in us-east-2 (Ohio) to match the platform region.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve management account ID
# ---------------------------------------------------------------------------
MGMT_ACCOUNT_ID="${1:-${AWS_ACCOUNT_ID:-}}"

if [[ -z "${MGMT_ACCOUNT_ID}" ]]; then
  echo "ERROR: Management account ID is required." >&2
  echo "  Usage: $0 <MGMT_ACCOUNT_ID>" >&2
  echo "  Or:    AWS_ACCOUNT_ID=<id> $0" >&2
  exit 1
fi

REGION="us-east-2"
BUCKET_NAME="odot-terraform-state-${MGMT_ACCOUNT_ID}"
TABLE_NAME="odot-terraform-locks"

echo "==> Bootstrap Terraform backend"
echo "    Account : ${MGMT_ACCOUNT_ID}"
echo "    Region  : ${REGION}"
echo "    Bucket  : ${BUCKET_NAME}"
echo "    Table   : ${TABLE_NAME}"
echo ""

# ---------------------------------------------------------------------------
# Helper: check if S3 bucket exists
# ---------------------------------------------------------------------------
bucket_exists() {
  aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" 2>/dev/null
}

# ---------------------------------------------------------------------------
# 1. Create S3 state bucket (if it does not already exist)
# ---------------------------------------------------------------------------
if bucket_exists; then
  echo "[SKIP] S3 bucket '${BUCKET_NAME}' already exists."
else
  echo "[CREATE] S3 bucket '${BUCKET_NAME}' ..."
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"
  echo "         Created."
fi

# ---------------------------------------------------------------------------
# 2. Block all public access on the bucket
# ---------------------------------------------------------------------------
echo "[CONFIG] Blocking all public access on '${BUCKET_NAME}' ..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --region "${REGION}" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo "         Done."

# ---------------------------------------------------------------------------
# 3. Enable versioning on the bucket
# ---------------------------------------------------------------------------
echo "[CONFIG] Enabling versioning on '${BUCKET_NAME}' ..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --region "${REGION}" \
  --versioning-configuration Status=Enabled
echo "         Done."

# ---------------------------------------------------------------------------
# 4. Enable SSE-KMS encryption on the bucket
#    Uses the aws/s3 AWS-managed key by default.
#    To use a customer-managed key, set KMS_KEY_ARN before running:
#      KMS_KEY_ARN=arn:aws:kms:us-east-2:123456789012:key/... ./bootstrap-backend.sh
# ---------------------------------------------------------------------------
KMS_KEY_ARN="${KMS_KEY_ARN:-}"

if [[ -n "${KMS_KEY_ARN}" ]]; then
  echo "[CONFIG] Enabling SSE-KMS encryption with CMK '${KMS_KEY_ARN}' ..."
  SSE_CONFIG=$(cat <<EOF
{
  "Rules": [{
    "ApplyServerSideEncryptionByDefault": {
      "SSEAlgorithm": "aws:kms",
      "KMSMasterKeyID": "${KMS_KEY_ARN}"
    },
    "BucketKeyEnabled": true
  }]
}
EOF
)
else
  echo "[CONFIG] Enabling SSE-KMS encryption with aws/s3 managed key ..."
  SSE_CONFIG=$(cat <<'EOF'
{
  "Rules": [{
    "ApplyServerSideEncryptionByDefault": {
      "SSEAlgorithm": "aws:kms"
    },
    "BucketKeyEnabled": true
  }]
}
EOF
)
fi

aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --region "${REGION}" \
  --server-side-encryption-configuration "${SSE_CONFIG}"
echo "         Done."

# ---------------------------------------------------------------------------
# 5. Create DynamoDB state-locking table (if it does not already exist)
# ---------------------------------------------------------------------------
table_exists() {
  aws dynamodb describe-table \
    --table-name "${TABLE_NAME}" \
    --region "${REGION}" \
    --query "Table.TableStatus" \
    --output text 2>/dev/null
}

if table_exists > /dev/null 2>&1; then
  echo "[SKIP] DynamoDB table '${TABLE_NAME}' already exists."
else
  echo "[CREATE] DynamoDB table '${TABLE_NAME}' ..."
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --region "${REGION}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --tags \
      Key=Environment,Value=management \
      Key=Project,Value=ODOTWebHosting \
      Key=Owner,Value=odot-platform-team

  echo -n "         Waiting for table to become ACTIVE ..."
  aws dynamodb wait table-exists \
    --table-name "${TABLE_NAME}" \
    --region "${REGION}"
  echo " Done."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "==> Bootstrap complete."
echo ""
echo "    Next steps:"
echo "    1. Update backend.tf files — replace MGMT_ACCOUNT_ID with: ${MGMT_ACCOUNT_ID}"
echo "    2. Run: terraform init"
echo "    3. Run: terraform plan"
