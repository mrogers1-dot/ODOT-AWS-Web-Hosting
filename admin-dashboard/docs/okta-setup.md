# Okta App Integration Setup

Step-by-step guide for configuring the Okta OIDC App Integration that federates with the ODOT Admin Dashboard's Cognito User Pool.

## Prerequisites

- Okta administrator access
- Knowledge of the Cognito domain prefix (e.g., `odot-dashboard-prod`)

## Steps

### 1. Create OIDC App Integration

1. Log in to the Okta Admin Console
2. Navigate to **Applications → Applications → Create App Integration**
3. Select **OIDC - OpenID Connect**
4. Select **Web Application**
5. Click **Next**

### 2. Configure General Settings

| Setting | Value |
|---------|-------|
| App integration name | `ODOT Admin Dashboard ({stage})` |
| Grant type | Authorization Code |
| Sign-in redirect URIs | `https://{cognito-domain}.auth.us-east-2.amazoncognito.com/oauth2/idpresponse` |
| Sign-out redirect URIs | `https://dashboard.internal.odot.ohio.gov/logout` |
| Controlled access | Limit access to selected groups |

### 3. Configure Scopes

Enable these scopes:
- `openid`
- `profile`
- `email`
- `groups` (required for role mapping)

### 4. Create Groups

Create two groups in Okta:

| Group Name | Purpose |
|------------|---------|
| `ODOT-Web-Developers` | View all, mutating actions on Dev/Test only |
| `ODOT-Web-Admins` | View all, mutating actions on all stages including Prod |

### 5. Assign Users

Assign users to the appropriate group based on their role. A user can be in both groups (Admin takes precedence).

### 6. Note the Credentials

After creating the app integration, note:
- **Client ID** — used in Terraform `okta_client_id` variable
- **Client Secret** — store in AWS Secrets Manager (see DEPLOYMENT-PREREQUISITES.md §12.2)
- **Issuer URL** — typically `https://your-org.okta.com/oauth2/default`

### 7. Test the Integration

1. Navigate to the dashboard URL
2. You should be redirected to Okta login
3. After authentication, you should land on the dashboard with your role applied
