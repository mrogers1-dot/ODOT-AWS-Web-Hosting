# ODOT Admin Dashboard

Operational management UI for the ODOT AWS Web Hosting platform. Provides real-time visibility into ECS services, CloudWatch metrics, and deployment status across all six account-stage environments.

## Features

- **Overview**: Tabbed view (Internal/External) with app status cards, sparklines, and task health
- **Detail View**: Per-app metrics (CPU, memory, requests, latency, errors), health panels, and stage sub-tabs
- **Actions**: Restart, Stop, Start, Scale, Rollback, View Logs, Search Logs, Block/Unblock IP, Maintenance Mode
- **RBAC**: Okta-federated authentication via Cognito. Developers can manage Dev/Test; Admins can manage all stages
- **Audit**: All mutating actions logged to DynamoDB with SNS notifications

## Architecture

```
Okta (IdP) → Cognito User Pool → Dashboard Frontend (React)
                                         ↓
                                  Dashboard Backend (Express)
                                         ↓
                              AWS APIs (ECS, CloudWatch, ALB, WAF, ECR)
                                         ↓
                              DynamoDB (audit) + SNS (notifications)
```

## Local Development

### Prerequisites

- Node.js 20+
- npm 10+
- AWS credentials configured (for API calls to ECS, CloudWatch, etc.)

### Setup

```bash
npm install
```

### Environment Variables

Create a `.env` file:

```env
PORT=3000
AWS_REGION=us-east-2
COGNITO_USER_POOL_ID=us-east-2_xxxxxxx
COGNITO_APP_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxx
CORS_ORIGIN=http://localhost:5173
AUDIT_TABLE_NAME=odot-dashboard-audit-dev
SNS_TOPIC_ARN=arn:aws:sns:us-east-2:577881328002:odot-alerts-internal
WAF_IP_SET_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
WAF_IP_SET_NAME=odot-dashboard-blocked-ips-dev
EXTERNAL_ACCOUNT_ROLE_ARN=arn:aws:iam::549136075921:role/odot-dashboard-cross-account-dev
```

### Run

```bash
# Backend (with hot reload)
npm run dev

# Frontend (separate terminal)
npx vite
```

### Test

```bash
npm test                # All tests
npm run test:backend    # Backend only
npm run test:frontend   # Frontend only
```

## API Endpoints

| Method | Path | Description | Role |
|--------|------|-------------|------|
| GET | `/health` | Health check | Public |
| GET | `/api/apps` | List all apps with status | Any |
| GET | `/api/apps/:name/:stage` | App detail | Any |
| POST | `/api/actions/:name/:stage/restart` | Restart service | Dev/Test: Developer, Prod: Admin |
| POST | `/api/actions/:name/:stage/stop` | Stop service | Dev/Test: Developer, Prod: Admin |
| POST | `/api/actions/:name/:stage/start` | Start service | Dev/Test: Developer, Prod: Admin |
| POST | `/api/actions/:name/:stage/scale` | Scale service | Dev/Test: Developer, Prod: Admin |
| POST | `/api/actions/:name/:stage/rollback` | Rollback to previous revision | Admin only |
| POST | `/api/actions/waf/block-ip` | Block IP address | Admin only |
| POST | `/api/actions/waf/unblock-ip` | Unblock IP address | Admin only |
| GET | `/api/logs/:name/:stage` | Recent logs | Any |
| POST | `/api/logs/:name/:stage/search` | Search logs | Any |
| GET | `/api/audit/:name/:stage` | Audit entries for app | Any |
| GET | `/api/audit/user/:userId` | Audit entries by user | Any |

## Docker Build

```bash
docker build -t odot-admin-dashboard .
docker run -p 3000:3000 --env-file .env odot-admin-dashboard
```

## Deployment

The dashboard deploys to the Internal account only via the same CI/CD pipeline pattern as other ODOT apps (unit test → scan → build → deploy). See `.github/workflows/ci-cd.yml`.
