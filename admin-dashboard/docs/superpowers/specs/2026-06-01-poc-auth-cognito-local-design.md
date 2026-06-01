# POC Auth: Cognito Local Users (No Okta)

**Date:** 2026-06-01
**Status:** Approved
**Scope:** Admin Dashboard authentication for POC/demo phase

## Context

The production auth architecture uses Okta as the identity provider, federated through AWS Cognito. For the POC, Okta is not yet provisioned and the setup overhead is too high for a demo. This spec defines a simplified auth approach that keeps the same Cognito-based backend validation but removes the Okta dependency.

## Decision

Use Cognito User Pool with local (email/password) users and the Cognito Hosted UI for login. No federated identity provider. Pre-seed two demo users with known roles.

## Architecture

### What Changes (vs Production Plan)

| Concern | Production | POC |
|---------|-----------|-----|
| Identity Provider | Okta (OIDC federation) | Cognito local users |
| Login UI | Okta → Cognito redirect | Cognito Hosted UI directly |
| User management | Okta groups | Manual `custom:role` attribute |
| MFA | TBD (likely required) | Disabled |
| Self-signup | Disabled | Disabled |

### What Stays the Same

- Cognito User Pool issues JWTs
- Backend validates JWTs against Cognito JWKS endpoint
- RBAC via `custom:role` claim (Admin vs Developer)
- Stage-gated access (Developers blocked from prod mutations)
- Audit logging of all actions

### Auth Flow (POC)

```
User → Dashboard URL
  → No token? Redirect to Cognito Hosted UI
  → User enters email/password
  → Cognito issues tokens (ID + access + refresh)
  → Redirect back to dashboard with auth code
  → Frontend exchanges code for tokens
  → Frontend stores tokens in session storage
  → API calls include Authorization: Bearer {id_token}
  → Backend validates JWT via JWKS (unchanged)
```

## Cognito User Pool Configuration

| Setting | Value |
|---------|-------|
| Pool name | `odot-dashboard-poc` |
| Sign-in options | Email |
| Password policy | Min 8, uppercase + lowercase + number + special |
| MFA | Off |
| Self-registration | Disabled |
| Custom attributes | `custom:role` (String, mutable) |
| Deletion protection | Disabled (POC only) |

## Cognito App Client Configuration

| Setting | Value |
|---------|-------|
| App client name | `odot-dashboard-poc-client` |
| Auth flows | Authorization Code grant |
| Scopes | `openid`, `email`, `profile` |
| Callback URLs | `http://localhost:3000/callback`, `https://{deployed-url}/callback` |
| Logout URLs | `http://localhost:3000/`, `https://{deployed-url}/` |
| Token validity | Access: 1hr, ID: 1hr, Refresh: 24hr |

## Cognito Hosted UI

| Setting | Value |
|---------|-------|
| Domain prefix | `odot-dashboard-poc` |
| Branding | Default Cognito styling (acceptable for POC) |

## Seed Users

| Email | `custom:role` | Temporary Password | Purpose |
|-------|---------------|-------------------|---------|
| `admin@odot.ohio.gov` | `Admin` | `TempPass123!` | Demo admin flows (prod mutations, rollback, IP blocking) |
| `developer@odot.ohio.gov` | `Developer` | `TempPass123!` | Demo developer flows (dev/test only) |

Users will be prompted to change password on first login (Cognito default behavior for admin-created users).

## Frontend Changes

- Add auth redirect logic on app load (check for tokens, redirect if missing)
- Add `/callback` route to handle the OAuth code exchange
- Store tokens in session storage
- Add `Authorization` header to all API requests
- Handle 401 responses by clearing tokens and redirecting to login
- Add logout button that clears tokens and redirects to Cognito logout endpoint

## Backend Changes

**None.** The existing `server/middleware/auth.ts` already:
- Validates JWTs against Cognito JWKS
- Extracts `custom:role` for RBAC
- Enforces stage-gated access

The only requirement is that the environment variables are set:
- `COGNITO_USER_POOL_ID` — the POC pool ID
- `AWS_REGION` — `us-east-2`

## Infrastructure (Terraform/CDK)

A POC-specific Cognito module or stack that provisions:
1. Cognito User Pool (config above)
2. Cognito App Client (config above)
3. Cognito Domain (hosted UI)
4. Seed users via AWS CLI script (not in IaC — ephemeral)

## Seed Script

A shell script (`scripts/seed-poc-users.sh`) that:
1. Creates both users with `admin-create-user`
2. Sets `custom:role` attribute
3. Sets temporary password
4. Outputs login instructions

## Upgrade Path to Production

When Okta is provisioned:
1. Add Okta as a federated IdP on the **same** Cognito User Pool
2. Configure attribute mapping: Okta `groups` → Cognito `custom:role`
3. Update Cognito App Client to allow the Okta IdP
4. Optionally remove seed users (or keep as break-glass accounts)
5. No backend code changes required
6. No frontend code changes required (Cognito handles the Okta redirect transparently)

## Deployment Configuration

### Environment Variables Required

**Backend (ECS Task Definition):**

| Variable | Value | Notes |
|----------|-------|-------|
| `COGNITO_USER_POOL_ID` | `us-east-2_XXXXXXX` | POC pool ID (output from Terraform/CDK) |
| `AWS_REGION` | `us-east-2` | Already set in current config |

**Frontend (Vite build-time — `VITE_` prefix required):**

| Variable | Value | Notes |
|----------|-------|-------|
| `VITE_COGNITO_DOMAIN` | `odot-dashboard-poc.auth.us-east-2.amazoncognito.com` | Cognito Hosted UI domain |
| `VITE_COGNITO_CLIENT_ID` | `<app-client-id>` | Output from Terraform/CDK |
| `VITE_COGNITO_REDIRECT_URI` | `http://localhost:3000/callback` (dev) or `https://{alb-url}/callback` (deployed) | Must match Cognito App Client config |
| `VITE_COGNITO_LOGOUT_URI` | `http://localhost:3000/` (dev) or `https://{alb-url}/` (deployed) | Must match Cognito App Client config |

### Where to Set These

| Context | Mechanism |
|---------|-----------|
| Local dev | `.env` file (gitignored) |
| CI/CD build | GitHub Actions secrets/variables → passed as `--build-arg` in Dockerfile or `.env` file generated in pipeline |
| ECS runtime | Task definition environment block (managed by Terraform/CDK) |

### Dockerfile Build Args (addition)

The Dockerfile needs build args for the frontend env vars so Vite can inline them at build time:

```dockerfile
# In the build stage, add:
ARG VITE_COGNITO_DOMAIN
ARG VITE_COGNITO_CLIENT_ID
ARG VITE_COGNITO_REDIRECT_URI
ARG VITE_COGNITO_LOGOUT_URI
```

### CI/CD Pipeline Update

The `build-push` job needs to pass build args:

```yaml
docker build \
  --build-arg VITE_COGNITO_DOMAIN=${{ vars.VITE_COGNITO_DOMAIN }} \
  --build-arg VITE_COGNITO_CLIENT_ID=${{ vars.VITE_COGNITO_CLIENT_ID }} \
  --build-arg VITE_COGNITO_REDIRECT_URI=${{ vars.VITE_COGNITO_REDIRECT_URI }} \
  --build-arg VITE_COGNITO_LOGOUT_URI=${{ vars.VITE_COGNITO_LOGOUT_URI }} \
  -t ${IMAGE}:${{ github.sha }} \
  -t ${IMAGE}:${{ github.ref_name }}-latest .
```

### Cognito Callback URL Must Match Deployed URL

The Cognito App Client's allowed callback/logout URLs must include the actual deployed URL (ALB or CloudFront). When the ECS service is deployed behind a load balancer, add that URL to the Cognito App Client config:

- Callback: `https://{alb-or-cloudfront-url}/callback`
- Logout: `https://{alb-or-cloudfront-url}/`

This is a one-time Terraform/CDK config update per environment.

## Out of Scope (POC)

- MFA enforcement
- Custom login UI (using Cognito Hosted UI as-is)
- Automated user provisioning/deprovisioning
- Session revocation workflows
- Token refresh logic (acceptable to require re-login after 1hr for POC)

## Risks

| Risk | Mitigation |
|------|-----------|
| POC auth pattern leaks to production | Clear documentation, separate Terraform module, `poc` naming |
| Seed passwords get committed | Passwords only in seed script, script is in `.gitignore` or uses env vars |
| No MFA for POC | Acceptable for internal demo; production will enforce MFA |
