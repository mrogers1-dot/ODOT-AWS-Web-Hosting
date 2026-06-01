#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# seed-poc-users.sh
#
# Creates POC demo users in the Cognito User Pool for the Admin Dashboard.
# These are local Cognito users (no Okta federation) for POC/demo purposes.
#
# Usage:
#   ./scripts/seed-poc-users.sh <user-pool-id>
#
# Environment variables (optional):
#   AWS_REGION         — defaults to us-east-2
#   POC_TEMP_PASSWORD  — defaults to TempPass123!
#
# Both users will be prompted to change their password on first login
# (Cognito FORCE_CHANGE_PASSWORD state).
#
# See: docs/superpowers/specs/2026-06-01-poc-auth-cognito-local-design.md
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

POOL_ID="${1:?Usage: $0 <user-pool-id>}"
REGION="${AWS_REGION:-us-east-2}"
TEMP_PASSWORD="${POC_TEMP_PASSWORD:-TempPass123!}"

echo "Seeding POC users into Cognito User Pool: $POOL_ID (region: $REGION)"
echo ""

# ── Admin user ────────────────────────────────────────────────────────────────
echo "Creating admin@odot.ohio.gov (role: Admin)..."
aws cognito-idp admin-create-user \
  --user-pool-id "$POOL_ID" \
  --username "admin@odot.ohio.gov" \
  --user-attributes \
    Name=email,Value=admin@odot.ohio.gov \
    Name=email_verified,Value=true \
    Name=custom:role,Value=Admin \
  --temporary-password "$TEMP_PASSWORD" \
  --message-action SUPPRESS \
  --region "$REGION" \
  > /dev/null

echo "  ✓ admin@odot.ohio.gov created"

# ── Developer user ────────────────────────────────────────────────────────────
echo "Creating developer@odot.ohio.gov (role: Developer)..."
aws cognito-idp admin-create-user \
  --user-pool-id "$POOL_ID" \
  --username "developer@odot.ohio.gov" \
  --user-attributes \
    Name=email,Value=developer@odot.ohio.gov \
    Name=email_verified,Value=true \
    Name=custom:role,Value=Developer \
  --temporary-password "$TEMP_PASSWORD" \
  --message-action SUPPRESS \
  --region "$REGION" \
  > /dev/null

echo "  ✓ developer@odot.ohio.gov created"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "POC users seeded successfully."
echo ""
echo "  Admin:     admin@odot.ohio.gov"
echo "  Developer: developer@odot.ohio.gov"
echo "  Password:  $TEMP_PASSWORD (must be changed on first login)"
echo ""
echo "Login at: https://$(aws cognito-idp describe-user-pool --user-pool-id "$POOL_ID" --region "$REGION" --query 'UserPool.Domain' --output text 2>/dev/null || echo '<cognito-domain>').auth.${REGION}.amazoncognito.com"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
