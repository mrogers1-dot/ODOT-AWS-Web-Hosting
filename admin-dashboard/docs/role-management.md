# Role Management

This document covers granting, revoking, and auditing access to the ODOT Admin Dashboard.

## Roles

| Role | Okta Group | Permissions |
|------|-----------|-------------|
| Developer | `ODOT-Web-Developers` | View all apps/metrics. Mutating actions on Dev and Test only. |
| Admin | `ODOT-Web-Admins` | View all apps/metrics. Mutating actions on all stages. Rollback and IP blocking. |

## Granting Access

1. Log in to the Okta Admin Console
2. Navigate to **Directory → Groups**
3. Select `ODOT-Web-Developers` or `ODOT-Web-Admins`
4. Click **Assign people** and add the user
5. The user can access the dashboard immediately (next login)

## Revoking Access

1. Remove the user from both `ODOT-Web-Developers` and `ODOT-Web-Admins` groups in Okta
2. The user's existing session remains valid until token expiry (max 1 hour)
3. For immediate revocation, sign the user out via Cognito:
   ```bash
   aws cognito-idp admin-user-global-sign-out \
     --user-pool-id <pool-id> \
     --username <user-sub> \
     --region us-east-2
   ```

## Emergency Revocation (All Users)

If a security incident requires revoking all dashboard access:

1. Disable the Okta App Integration (prevents new logins)
2. Invalidate all Cognito sessions:
   ```bash
   # There's no bulk sign-out API — disable the app client temporarily
   aws cognito-idp update-user-pool-client \
     --user-pool-id <pool-id> \
     --client-id <client-id> \
     --supported-identity-providers "" \
     --region us-east-2
   ```
3. Investigate and resolve the incident
4. Re-enable the identity provider and notify users

## Auditing Access

All dashboard actions are logged to DynamoDB. Query by user:

```bash
aws dynamodb query \
  --table-name odot-dashboard-audit-prod \
  --index-name user-index \
  --key-condition-expression "userId = :uid" \
  --expression-attribute-values '{":uid":{"S":"<user-sub>"}}' \
  --scan-index-forward false \
  --limit 20 \
  --region us-east-2
```

Daily audit exports are stored immutably in S3 (`odot-dashboard-audit-archive-{stage}`) with 365-day Object Lock retention.
