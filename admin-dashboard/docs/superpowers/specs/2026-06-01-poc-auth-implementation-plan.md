# Implementation Plan: POC Auth (Cognito Local, No Okta)

**Spec:** `2026-06-01-poc-auth-cognito-local-design.md`
**Date:** 2026-06-01

## Overview

This plan implements the POC auth approach: Cognito User Pool with local users, Hosted UI login, and no Okta federation. The backend middleware is unchanged. Work is split into 4 phases.

---

## Phase 1: Infrastructure — POC Cognito Module

Create a POC-specific Terraform configuration that provisions Cognito without the Okta IdP.

### Task 1.1: Create POC Cognito Terraform file

**File:** `odot-aws-platform/modules/admin-dashboard/cognito-poc.tf`

Create an alternate Cognito config (controlled by a `use_okta` variable) that:
- Provisions the same User Pool (pool name: `odot-dashboard-{stage}`)
- Skips the `aws_cognito_identity_provider.okta` resource
- Sets `supported_identity_providers = ["COGNITO"]` on the app client (local login)
- Removes `generate_secret = true` (not needed for public client with PKCE)
- Keeps all other config identical (domain, scopes, token validity, callback URLs)

**Approach:** Use a `count` or `for_each` conditional on the existing Okta IdP resource, controlled by a new `enable_okta_federation` variable. This way the same module works for both POC and production.

### Task 1.2: Add `enable_okta_federation` variable

**File:** `odot-aws-platform/modules/admin-dashboard/variables.tf`

```hcl
variable "enable_okta_federation" {
  description = "Whether to configure Okta as a federated IdP. Set to false for POC (Cognito local users only)."
  type        = bool
  default     = true
}
```

Make `okta_issuer_url`, `okta_client_id`, and `okta_client_secret` optional (only required when `enable_okta_federation = true`).

### Task 1.3: Update `cognito.tf` with conditional Okta resources

**File:** `odot-aws-platform/modules/admin-dashboard/cognito.tf`

- Add `count = var.enable_okta_federation ? 1 : 0` to `aws_cognito_identity_provider.okta`
- Update `aws_cognito_user_pool_client.dashboard`:
  - `supported_identity_providers = var.enable_okta_federation ? ["Okta"] : ["COGNITO"]`
  - `generate_secret = var.enable_okta_federation` (public client for POC, confidential for prod)
- Add password policy to the user pool (needed for local users):
  ```hcl
  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }
  ```

### Task 1.4: Update outputs

**File:** `odot-aws-platform/modules/admin-dashboard/outputs.tf`

Update `cognito_domain` output description to remove "Okta-federated" reference (it's conditional now).

---

## Phase 2: Seed Script

### Task 2.1: Create user seed script

**File:** `admin-dashboard/scripts/seed-poc-users.sh`

```bash
#!/usr/bin/env bash
# Seeds POC demo users into the Cognito User Pool.
# Usage: ./seed-poc-users.sh <user-pool-id>
# Requires: AWS CLI configured with appropriate permissions.

set -euo pipefail

POOL_ID="${1:?Usage: $0 <user-pool-id>}"
REGION="${AWS_REGION:-us-east-2}"
TEMP_PASSWORD="${POC_TEMP_PASSWORD:-TempPass123!}"

# Create Admin user
aws cognito-idp admin-create-user \
  --user-pool-id "$POOL_ID" \
  --username "admin@odot.ohio.gov" \
  --user-attributes Name=email,Value=admin@odot.ohio.gov Name=email_verified,Value=true Name=custom:role,Value=Admin \
  --temporary-password "$TEMP_PASSWORD" \
  --message-action SUPPRESS \
  --region "$REGION"

# Create Developer user
aws cognito-idp admin-create-user \
  --user-pool-id "$POOL_ID" \
  --username "developer@odot.ohio.gov" \
  --user-attributes Name=email,Value=developer@odot.ohio.gov Name=email_verified,Value=true Name=custom:role,Value=Developer \
  --temporary-password "$TEMP_PASSWORD" \
  --message-action SUPPRESS \
  --region "$REGION"

echo "✓ POC users created. Both users will be prompted to change password on first login."
echo ""
echo "  Admin:     admin@odot.ohio.gov / $TEMP_PASSWORD"
echo "  Developer: developer@odot.ohio.gov / $TEMP_PASSWORD"
```

### Task 2.2: Add script to `.gitignore` note

Add a comment in the script header noting that the password should come from an env var in CI, not be hardcoded in committed files.

---

## Phase 3: Frontend Auth Flow

### Task 3.1: Create auth utility module

**File:** `admin-dashboard/src/auth.ts`

Exports:
- `getAuthConfig()` — reads `VITE_COGNITO_*` env vars, returns config object
- `getLoginUrl()` — constructs Cognito Hosted UI authorize URL
- `getLogoutUrl()` — constructs Cognito logout URL
- `exchangeCodeForTokens(code: string)` — POST to Cognito `/oauth2/token` endpoint
- `getStoredTokens()` — reads tokens from sessionStorage
- `storeTokens(tokens)` — saves to sessionStorage
- `clearTokens()` — removes from sessionStorage
- `isAuthenticated()` — checks if valid (non-expired) token exists
- `getAuthHeader()` — returns `{ Authorization: 'Bearer ...' }` or null

### Task 3.2: Create callback route component

**File:** `admin-dashboard/src/components/AuthCallback.tsx`

- Reads `code` from URL query params
- Calls `exchangeCodeForTokens(code)`
- On success, stores tokens and redirects to `/`
- On failure, shows error and link to retry login

### Task 3.3: Update App.tsx with auth gate

**File:** `admin-dashboard/src/App.tsx`

- On mount, check `isAuthenticated()`
- If not authenticated and no `code` in URL → redirect to `getLoginUrl()`
- If `code` in URL → render `<AuthCallback />`
- If authenticated → render dashboard
- Add logout button in header that calls `clearTokens()` + redirects to `getLogoutUrl()`

### Task 3.4: Create API client with auth header

**File:** `admin-dashboard/src/api.ts`

- Wraps `fetch` with automatic `Authorization` header injection via `getAuthHeader()`
- On 401 response, calls `clearTokens()` and redirects to login
- All existing API calls should use this client

---

## Phase 4: Deployment Config Updates

### Task 4.1: Update Dockerfile with build args

**File:** `admin-dashboard/Dockerfile`

Add to the build stage (Stage 2):
```dockerfile
ARG VITE_COGNITO_DOMAIN
ARG VITE_COGNITO_CLIENT_ID
ARG VITE_COGNITO_REDIRECT_URI
ARG VITE_COGNITO_LOGOUT_URI
```

### Task 4.2: Update CI/CD pipeline

**File:** `admin-dashboard/.github/workflows/ci-cd.yml`

Update the `build-push` job's docker build command to pass `--build-arg` for each `VITE_COGNITO_*` variable from GitHub Actions vars.

### Task 4.3: Create `.env.example` for local dev

**File:** `admin-dashboard/.env.example`

```env
# Backend
COGNITO_USER_POOL_ID=us-east-2_XXXXXXX
AWS_REGION=us-east-2

# Frontend (Vite)
VITE_COGNITO_DOMAIN=odot-dashboard-poc.auth.us-east-2.amazoncognito.com
VITE_COGNITO_CLIENT_ID=your-app-client-id
VITE_COGNITO_REDIRECT_URI=http://localhost:3000/callback
VITE_COGNITO_LOGOUT_URI=http://localhost:3000/
```

### Task 4.4: Create POC auth setup documentation

**File:** `admin-dashboard/docs/poc-auth-setup.md`

Document:
- What this POC auth approach is and why (link to spec)
- How to deploy the Cognito resources (`terraform apply` with `enable_okta_federation = false`)
- How to run the seed script
- How to configure local dev env vars
- How to log in and test both roles
- How to upgrade to Okta when ready (link to existing okta-setup.md)

---

## Execution Order

```
Phase 1 (Infra) → Phase 2 (Seed Script) → Phase 3 (Frontend) → Phase 4 (Deployment)
```

Phases 1 and 2 can be done in parallel. Phase 3 depends on knowing the Cognito config shape. Phase 4 ties everything together.

## Verification

- [ ] `terraform plan` with `enable_okta_federation = false` shows Cognito pool + client, no Okta IdP
- [ ] `terraform plan` with `enable_okta_federation = true` shows existing behavior (no regression)
- [ ] Seed script creates users successfully against a deployed pool
- [ ] Frontend redirects to Cognito Hosted UI when unauthenticated
- [ ] Login with `admin@odot.ohio.gov` → dashboard loads, role = Admin
- [ ] Login with `developer@odot.ohio.gov` → dashboard loads, role = Developer
- [ ] API calls include Bearer token, backend validates successfully
- [ ] 401 on expired token redirects to login
- [ ] Logout clears session and redirects to Cognito logout
