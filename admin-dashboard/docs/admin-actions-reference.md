# Admin Actions Reference

Complete reference for all administrative actions available in the ODOT Admin Dashboard.

## Action Summary

| # | Action | API Endpoint | Required Role | Logged |
|---|--------|-------------|---------------|--------|
| 1 | Restart Service | `POST /api/actions/:name/:stage/restart` | Dev/Test: Developer, Prod: Admin | Yes |
| 2 | Stop Service | `POST /api/actions/:name/:stage/stop` | Dev/Test: Developer, Prod: Admin | Yes |
| 3 | Start Service | `POST /api/actions/:name/:stage/start` | Dev/Test: Developer, Prod: Admin | Yes |
| 4 | Scale Up | `POST /api/actions/:name/:stage/scale` | Dev/Test: Developer, Prod: Admin | Yes |
| 5 | Scale Down | `POST /api/actions/:name/:stage/scale` | Dev/Test: Developer, Prod: Admin | Yes |
| 6 | Stop Specific Task | `POST /api/actions/:name/:stage/stop-task` | Dev/Test: Developer, Prod: Admin | Yes |
| 7 | Rollback | `POST /api/actions/:name/:stage/rollback` | Admin only (any stage) | Yes |
| 8 | View Logs | `GET /api/logs/:name/:stage` | Any authenticated | No |
| 9 | Search Logs | `POST /api/logs/:name/:stage/search` | Any authenticated | No |
| 10 | Enable Maintenance Mode | `POST /api/actions/:name/:stage/maintenance` | Dev/Test: Developer, Prod: Admin | Yes |
| 11 | Disable Maintenance Mode | `POST /api/actions/:name/:stage/maintenance` | Dev/Test: Developer, Prod: Admin | Yes |
| 12 | Block IP | `POST /api/actions/waf/block-ip` | Admin only | Yes |
| 13 | Unblock IP | `POST /api/actions/waf/unblock-ip` | Admin only | Yes |
| 14 | Disable Auto-Scaling | `POST /api/actions/:name/:stage/autoscaling/disable` | Dev/Test: Developer, Prod: Admin | Yes |
| 15 | Re-enable Auto-Scaling | `POST /api/actions/:name/:stage/autoscaling/enable` | Dev/Test: Developer, Prod: Admin | Yes |
| 16 | Override Scaling Bounds | `POST /api/actions/:name/:stage/autoscaling/override` | Dev/Test: Developer, Prod: Admin | Yes |

## Action Details

### 1. Restart Service

**What it does**: Forces a new ECS deployment. All tasks are replaced with fresh instances using the current task definition.

**AWS API called**: `ecs:UpdateService` with `forceNewDeployment = true`

**When to use**: Application is in a bad state, memory leak suspected, or configuration change needs to take effect.

**Rollback if something goes wrong**: ECS circuit breaker automatically rolls back if new tasks fail health checks. No manual action needed.

### 2. Stop Service

**What it does**: Sets the ECS service desired count to 0. All running tasks are drained and stopped.

**AWS API called**: `ecs:UpdateService` with `desiredCount = 0`

**When to use**: Emergency — application is causing harm (data corruption, cascading failures). Use sparingly.

**Rollback**: Use "Start Service" to restore desired count to minimum (2).

### 3. Start Service

**What it does**: Restores the ECS service desired count to the minimum (2 tasks).

**AWS API called**: `ecs:UpdateService` with `desiredCount = 2`

**When to use**: After a "Stop Service" action, when the issue is resolved.

### 4–5. Scale Up / Scale Down

**What it does**: Increases or decreases the desired task count by a specified amount.

**AWS API called**: `ecs:UpdateService` with `desiredCount = current ± N`

**Constraints**: Cannot go below 0 or above 50 (auto-scaling bounds).

**When to use**: Anticipated traffic spike (scale up before event) or cost reduction during known low-traffic periods.

### 6. Stop Specific Task

**What it does**: Kills one specific ECS task. ECS automatically launches a replacement.

**AWS API called**: `ecs:StopTask`

**When to use**: One task is misbehaving (stuck, high CPU) but others are healthy. Targeted remediation without full restart.

### 7. Rollback

**What it does**: Updates the ECS service to use a previous task definition revision.

**AWS API called**: `ecs:UpdateService` with `taskDefinition = <previous-revision-arn>`

**Required role**: Admin only (regardless of stage) — rollbacks can have significant impact.

**When to use**: A deployment introduced a bug that wasn't caught by health checks. The circuit breaker didn't trigger but the app is misbehaving.

**Rollback if something goes wrong**: Deploy the current (newer) revision again via the CI/CD pipeline.

### 8–9. View / Search Logs

**What it does**: Retrieves recent CloudWatch log events or runs a Logs Insights query.

**AWS API called**: `logs:FilterLogEvents` or `logs:StartQuery` + `logs:GetQueryResults`

**Not logged to audit**: Read-only operations don't generate audit entries.

### 10–11. Maintenance Mode

**What it does**: Configures the ALB listener rule to return a static HTTP 503 maintenance page instead of forwarding to ECS tasks.

**AWS API called**: `elasticloadbalancing:ModifyRule`

**When to use**: Planned maintenance window, or emergency while investigating an issue.

### 12–13. Block / Unblock IP

**What it does**: Adds or removes an IP address from the WAF IP set (block list).

**AWS API called**: `wafv2:GetIPSet` + `wafv2:UpdateIPSet`

**Required role**: Admin only — IP blocking affects all users from that IP.

**Format**: IP must be in CIDR notation (e.g., `1.2.3.4/32` for a single IP).

**Capacity**: WAF IP sets support up to 10,000 addresses.

### 14–16. Auto-Scaling Controls

**What it does**:
- **Disable**: Sets min = max = current count (freezes scaling)
- **Re-enable**: Restores original bounds (min=2, max=50)
- **Override**: Temporarily changes min/max to custom values

**AWS API called**: `application-autoscaling:RegisterScalableTarget`

**When to use**: During incident investigation (prevent scale-in while debugging) or load testing (set specific task count).

## Audit Log Format

Every mutating action creates an entry in DynamoDB:

```json
{
  "pk": "fleet-tracker#prod",
  "sk": "2024-01-15T10:30:00.000Z",
  "userId": "okta-user-sub-id",
  "email": "john.doe@odot.ohio.gov",
  "role": "Admin",
  "action": "POST /api/actions/fleet-tracker/prod/restart",
  "body": {},
  "statusCode": 200,
  "duration": 1250,
  "ttl": 1737100200
}
```

A Slack notification is also sent: `"john.doe@odot.ohio.gov performed restart on fleet-tracker (prod) at 2024-01-15T10:30:00Z"`
