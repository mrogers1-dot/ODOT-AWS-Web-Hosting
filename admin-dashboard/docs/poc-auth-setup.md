# POC Auth Setup Guide

> **This is a POC-only authentication setup.** Production will use Okta federation.
> See [okta-setup.md](./okta-setup.md) for the production auth architecture.

## Overview

For the POC/demo phase, the Admin Dashboard uses **Cognito local users** instead of Okta federation. Users log in directly via the Cognito Hosted UI with email and password. The backend JWT validation is identical to production — only the identity source changes.

**Design spec:** [2026-06-01-poc-auth-cognito-local-design.md](./superpowers/specs/2026-06-01-poc-auth-cognito-local-design.md)

## Prerequisites

- AWS CLI configured with permissions to manage Cognito
- Terraform installed (for infrastructure provisioning)
- Node.js 20+ (for local development)

## Step 1: Deploy Cognito Resources

From the `odot-aws-platform` directory, deploy the admin-dashboard module with Okta disabled:

```hcl
# In your stack/environment tfvars:
enable_okta_federation = false
stage                  = "dev"
cognito_domain_prefix  = "odot-dashboard-poc"
callback_urls          = ["http://localhost:3000/callback"]
logout_urls            = ["http://localhost:3000/"]
```

```bash
terraform plan -target=module.admin_dashboard
terraform apply -target=module.admin_dashboard
```

Note the outputs:
- `cognito_user_pool_id`
- `cognito_app_client_id`
- `cognito_domain`

## Step 2: Seed Demo Users

```bash
cd admin-dashboard
./scripts/seed-poc-users.sh <cognito_user_pool_id>
```

This creates:
| Email | Role | Temp Password |
|-------|------|---------------|
| `admin@odot.ohio.gov` | Admin | `TempPass123!` |
| `developer@odot.ohio.gov` | Developer | `TempPass123!` |

Both users must change their password on first login.

## Step 3: Configure Local Environment

Copy the example env file and fill in the values from Step 1:

```bash
cp .env.example .env
```

Edit `.env`:
```env
COGNITO_USER_POOL_ID=<from terraform output>
AWS_REGION=us-east-2
VITE_COGNITO_DOMAIN=<from terraform output>
VITE_COGNITO_CLIENT_ID=<from terraform output>
VITE_COGNITO_REDIRECT_URI=http://localhost:3000/callback
VITE_COGNITO_LOGOUT_URI=http://localhost:3000/
```

## Step 4: Run Locally

```bash
npm install
npm run dev
```

Navigate to `http://localhost:3000`. You'll be redirected to the Cognito Hosted UI. Log in with one of the demo accounts.

## Testing Both Roles

- **Admin** (`admin@odot.ohio.gov`): Can perform all actions including production mutations, rollback, and IP blocking.
- **Developer** (`developer@odot.ohio.gov`): Can view everything but can only perform mutations on Dev/Test stages.

## Upgrading to Okta (Production)

When Okta is provisioned:

1. Set `enable_okta_federation = true` in your tfvars
2. Provide `okta_issuer_url`, `okta_client_id`, `okta_client_secret`
3. Run `terraform apply`
4. No frontend or backend code changes needed

See [okta-setup.md](./okta-setup.md) for full Okta configuration details.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "Invalid redirect URI" | Ensure `callback_urls` in Terraform matches `VITE_COGNITO_REDIRECT_URI` exactly |
| "Invalid client" | Check `VITE_COGNITO_CLIENT_ID` matches the Terraform output |
| Token exchange fails | Verify the Cognito domain is correct and the app client has `code` grant enabled |
| `custom:role` is empty | Re-run the seed script or manually set the attribute via AWS Console |
| CORS errors on token endpoint | The Cognito token endpoint handles CORS natively — check for proxy issues |
