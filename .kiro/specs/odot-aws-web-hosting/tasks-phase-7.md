# Phase 7: Admin Dashboard — Infrastructure, Backend, Frontend, Deploy, Docs

## Verification Gate
Final full-system checkpoint: all platform tests + dashboard backend tests + dashboard frontend tests + smoke tests pass.

## Dependencies
Phase 6 must be complete and passing (platform must be fully operational before adding dashboard on top).

---

## Tasks

- [x] 18. Implement `modules/admin-dashboard` — Cognito, DynamoDB audit, IAM roles
  - [x] 18.1 **RED**: Write unit test for admin-dashboard module. Assert Cognito User Pool has Okta as federated IdP. Assert DynamoDB table has TTL enabled. Assert cross-account role trust policy allows Internal_Account task role. Assert dashboard task role has ECS, CloudWatch, ALB, WAF, Auto-Scaling permissions scoped to `WebHosting-*`. Test should FAIL. _Req: 14.1, 14.29, 14.30_
  - [x] 18.2 **GREEN**: Write `modules/admin-dashboard/cognito.tf`. Create `aws_cognito_user_pool`, `aws_cognito_identity_provider` (Okta OIDC), `aws_cognito_user_pool_client` (authorization code flow), `aws_cognito_user_pool_domain`. Configure attribute mapping: Okta groups → `custom:role`. _Req: 14.1, 14.2_
  - [x] 18.3 **GREEN**: Write `modules/admin-dashboard/dynamodb.tf`. Create `aws_dynamodb_table` `odot-dashboard-audit` with partition key `pk` (app#stage), sort key `sk` (timestamp), GSI `user-index`, TTL on `ttl` attribute, PAY_PER_REQUEST billing. _Req: 14.18_
  - [x] 18.4 **GREEN**: Write `modules/admin-dashboard/iam.tf`. Create dashboard task role with permissions for ECS, CloudWatch, Logs, ALB, WAF, Auto-Scaling, DynamoDB, SNS, STS:AssumeRole. Create cross-account role in External_Account with same permissions scoped to external resources. Create WAF IP set for managed blocking. _Req: 14.29, 14.30_
  - [x] 18.5 **GREEN**: Write `modules/admin-dashboard/variables.tf`, `outputs.tf`. Output `cognito_user_pool_id`, `cognito_app_client_id`, `cognito_domain`, `audit_table_name`, `dashboard_task_role_arn`, `cross_account_role_arn`. Test from 18.1 should PASS. _Req: 14.1, 14.29, 14.30_
  - [x] 18.6 **REFACTOR**: Add inline comments — Okta attribute mapping, cross-account trust policy, permission scoping rationale, TTL purpose. _Req: 12.5_

- [x] 19. Implement Admin Dashboard backend API
  - [x] 19.1 **RED**: Write API integration tests. Assert GET `/api/apps` returns app list with status. Assert POST `/api/apps/:name/restart` with Developer role + Prod stage returns 403. Assert POST `/api/apps/:name/restart` with Admin role + Prod stage returns 200. Assert all mutating actions create audit log entries. Tests should FAIL. _Req: 14.2, 14.3, 14.18_
  - [x] 19.2 **GREEN**: Scaffold `admin-dashboard/server/` — Express app, TypeScript config, auth middleware (JWT validation against Cognito JWKS), RBAC middleware (role extraction from `custom:role` claim). _Req: 14.1, 14.2, 14.3_
  - [x] 19.3 **GREEN**: Implement `server/services/ecs.ts` — ECS API wrapper: listServices, describeServices, describeTasks, updateService (restart/stop/start/scale), stopTask, describeTaskDefinition, registerTaskDefinition (rollback). _Req: 14.16, 14.20, 14.22_
  - [x] 19.4 **GREEN**: Implement `server/services/cloudwatch.ts` — CloudWatch metrics (CPU, memory, request count, latency, 5xx, 4xx, connections), describeAlarms, getLogs, startQuery/getQueryResults. _Req: 14.12, 14.13, 14.15, 14.20_
  - [x] 19.5 **GREEN**: Implement `server/services/alb.ts` — describeTargetHealth, modifyRule (maintenance mode toggle). _Req: 14.20, 14.24_
  - [x] 19.6 **GREEN**: Implement `server/services/waf.ts` — getIPSet, updateIPSet (block/unblock). _Req: 14.25_
  - [x] 19.7 **GREEN**: Implement `server/services/ecr.ts` — listImages, describeImageScanFindings. _Req: 14.23_
  - [x] 19.8 **GREEN**: Implement `server/services/autoscaling.ts` — describeScalingActivities, registerScalableTarget (disable/enable/override). _Req: 14.26_
  - [x] 19.9 **GREEN**: Implement `server/services/crossAccount.ts` — STS assumeRole helper for External_Account. _Req: 14.29_
  - [x] 19.10 **GREEN**: Implement `server/services/envVars.ts` — Read active task definition, return plain `environment` key-value pairs unmasked and `secrets` references with values replaced by `***REDACTED***`. Never resolve secret ARNs to actual values. _Req: 14.27_
  - [x] 19.11 **GREEN**: Implement `server/middleware/auditLog.ts` — auto-log all mutations to DynamoDB + publish to SNS. _Req: 14.18, 14.19_
  - [x] 19.12 **GREEN**: Implement all route handlers (`server/routes/apps.ts`, `actions.ts`, `logs.ts`, `audit.ts`). Wire RBAC: Developer=Dev/Test mutating, Admin=all. Rollback and Block/Unblock IP require Admin regardless of stage. Tests from 19.1 should PASS. _Req: 14.16–14.28_
  - [x] 19.13 **REFACTOR**: Add error handling (cross-account failures, ECS API errors, WAF capacity), input validation, rate limiting on mutating endpoints. _Req: 14.3_

- [x] 20. Implement Admin Dashboard frontend
  - [x] 20.1 **RED**: Write frontend component tests. Assert AppCard renders status badge (green/yellow/red) based on props. Assert ActionsPanel hides Prod buttons for Developer role. Assert ConfirmDialog displays correct action/app/stage text. Tests should FAIL. _Req: 14.7, 14.8, 14.9, 14.16, 14.17_
  - [x] 20.2 **GREEN**: Scaffold `admin-dashboard/src/` — React + TypeScript + Tailwind + Vite. Implement auth flow (Cognito hosted UI redirect, token storage, auto-refresh). _Req: 14.1, 14.5_
  - [x] 20.3 **GREEN**: Implement Overview page — tabbed layout (Internal/External), AppCard grid with status indicator, sparkline (last 1hr), task health summary. Polling every 30s with "last updated" display. _Req: 14.7, 14.8, 14.9, 14.10_
  - [x] 20.4 **GREEN**: Implement Detail page — stage sub-tabs (Dev/Test/Prod), MetricsPanel (site metrics + graphs), app health panel, user stats panel. _Req: 14.11, 14.12, 14.13, 14.14, 14.15_
  - [x] 20.5 **GREEN**: Implement ActionsPanel — service lifecycle buttons (Restart, Stop, Start, Scale Up/Down), diagnostics (View Logs, Search Logs, Tasks, Health), deployment (Rollback, History, Images), traffic (Maintenance Mode, Block/Unblock IP), auto-scaling controls, env vars panel. RBAC: hide/disable Prod actions for Developers, hide Rollback/Block IP for non-Admins. _Req: 14.16, 14.20–14.28_
  - [x] 20.6 **GREEN**: Implement ConfirmDialog — reusable modal with action/app/stage context, confirm/cancel buttons. _Req: 14.17_
  - [x] 20.7 **GREEN**: Implement LogViewer — recent logs stream, search interface (query input, time range, results table). _Req: 14.20_
  - [x] 20.8 **GREEN**: Implement DeployHistory and ImageList panels. Tests from 20.1 should PASS. _Req: 14.21, 14.23_
  - [x] 20.9 **REFACTOR**: Polish UI — consistent spacing, responsive layout, loading states, error states, empty states, accessibility (ARIA labels, keyboard navigation). _Req: 14.5_

- [x] 21. Containerize and deploy Admin Dashboard
  - [x] 21.1 **RED**: Write test asserting Dockerfile exists, builds successfully, and runs on port 3000 with non-root user. Test should FAIL. _Req: 14.5, 14.6_
  - [x] 21.2 **GREEN**: Write `admin-dashboard/Dockerfile` — multi-stage build (node:20-alpine), frontend build → backend build → production image, non-root user, health check endpoint. _Req: 14.5_
  - [x] 21.3 **GREEN**: Write `admin-dashboard/.github/workflows/ci-cd.yml` — same pipeline pattern as app-template (unit test → scan → build → deploy). Deploy to Internal_Account only. _Req: 14.6_
  - [x] 21.4 **GREEN**: Add dashboard to Internal_Account stack via `app-service` module call with appropriate variables (Cognito env vars, DynamoDB table name, cross-account role ARN). Test from 21.1 should PASS. _Req: 14.5, 14.6_
  - [x] 21.5 **REFACTOR**: Optimize Docker image size, add health check endpoint, configure graceful shutdown. _Req: 14.5_

- [x] 22. Write Admin Dashboard documentation
  - [x] 22.1 **RED**: Write validation test asserting all required dashboard docs exist. Test should FAIL.
  - [x] 22.2 **GREEN**: Write `admin-dashboard/README.md` — local dev setup, env vars, API endpoints, frontend build, Docker build, deployment. _Req: 14.35_
  - [x] 22.3 **GREEN**: Write `admin-dashboard/docs/okta-setup.md` — step-by-step Okta App Integration (OIDC type, auth code flow, redirect URIs, scopes, groups, user assignment, testing). _Req: 14.4, 14.35_
  - [x] 22.4 **GREEN**: Write `admin-dashboard/docs/cognito-setup.md` — User Pool creation, Okta IdP federation, attribute mapping (groups → custom:role), app client, hosted UI domain. _Req: 14.4, 14.35_
  - [x] 22.5 **GREEN**: Write `admin-dashboard/docs/role-management.md` — grant/revoke access, Okta group management, audit access, emergency revocation. _Req: 14.4, 14.35_
  - [x] 22.6 **GREEN**: Write `admin-dashboard/docs/admin-actions-reference.md` — all 16 actions documented: what each does, API called, required role, what gets logged, rollback if something goes wrong. _Req: 14.35_
  - [x] 22.7 **GREEN**: Update `DEPLOYMENT-PREREQUISITES.md` — new section covering dashboard setup (Okta, Cognito, cross-account role, DynamoDB, verification). _Req: 14.31_
  - [x] 22.8 **GREEN**: Update `odot-aws-platform/README.md` — add `modules/admin-dashboard` reference, update repo structure, update architecture section. _Req: 14.32_
  - [x] 22.9 **GREEN**: Update `odot-aws-platform/docs/runbook.md` — add "Admin Dashboard Operations" section. _Req: 14.33_
  - [x] 22.10 **GREEN**: Write `odot-aws-platform/docs/architecture/admin-dashboard.md` — Mermaid diagram of Okta → Cognito → Dashboard → AWS APIs flow. Test from 22.1 should PASS. _Req: 14.34_
  - [x] 22.11 **REFACTOR**: Review all docs for consistency, cross-references, and completeness. _Req: 14.31–14.35_

- [x] 23. Final checkpoint — Verify entire platform including dashboard
  - [x] 23.1 Run all platform tests (`go test ./...`)
  - [x] 23.2 Run dashboard backend tests (`cd admin-dashboard && npm test`)
  - [x] 23.3 Run dashboard frontend tests (`cd admin-dashboard && npm run test:frontend`)
  - [x] 23.4 Run smoke tests including dashboard verification
  - [x] 23.5 Resolve any failures

---

## Phase 7 Checkpoint (FINAL)

- [x] All platform Go tests pass
- [x] Dashboard backend tests pass
- [x] Dashboard frontend tests pass
- [x] Smoke tests pass (including dashboard)
- [x] All documentation validation tests pass
- [x] Project is complete and ready for deployment
