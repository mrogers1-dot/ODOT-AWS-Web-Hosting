# Cognito User Pool Setup

The Cognito User Pool is provisioned automatically by the `modules/admin-dashboard` Terraform module. This document explains the configuration for reference and troubleshooting.

## What Terraform Creates

| Resource | Purpose |
|----------|---------|
| Cognito User Pool | Identity broker between Okta and the dashboard |
| Cognito Identity Provider (Okta) | OIDC federation with Okta |
| Cognito App Client | Authorization code flow for the dashboard frontend |
| Cognito Domain | Hosted UI login page URL |

## Attribute Mapping

| Okta Claim | Cognito Attribute | Purpose |
|------------|-------------------|---------|
| `email` | `email` | User identification |
| `sub` | `username` | Unique user ID |
| `groups` | `custom:role` | RBAC (Admin vs Developer) |

## How Authentication Works

1. User navigates to dashboard → redirected to Cognito hosted UI
2. Cognito redirects to Okta for authentication
3. Okta authenticates user, returns authorization code to Cognito
4. Cognito exchanges code for tokens (ID + access + refresh)
5. Frontend stores tokens, sends `Authorization: Bearer {id_token}` on API calls
6. Backend validates JWT against Cognito JWKS endpoint
7. Backend extracts `custom:role` claim for RBAC decisions

## Token Validity

| Token | Validity | Refresh |
|-------|----------|---------|
| Access token | 1 hour | Via refresh token |
| ID token | 1 hour | Via refresh token |
| Refresh token | 24 hours | User must re-authenticate |

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| "Invalid redirect URI" | Callback URL mismatch | Verify `callback_urls` in Terraform matches Okta config |
| "Invalid client" | Wrong client ID | Check `cognito_app_client_id` output |
| Token validation fails | JWKS endpoint unreachable | Check VPC endpoints (internal account needs `cognito-idp` endpoint) |
| `custom:role` is empty | Okta not sending groups claim | Verify Okta app has `groups` scope and attribute mapping |
