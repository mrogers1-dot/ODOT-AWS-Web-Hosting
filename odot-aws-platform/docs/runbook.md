# ODOT AWS Web Hosting — Operations Runbook

This runbook documents common operational procedures for the ODOT AWS Web Hosting platform. It covers application onboarding, alarm response, key rotation, notification channel management, deployment troubleshooting, Fargate Spot interruption handling, VPC endpoint issues, TLS certificate management, WAF troubleshooting, resilience testing, and Admin Dashboard operations.

---

## Table of Contents

1. [Onboarding a New Application](#1-onboarding-a-new-application)
2. [Responding to CloudWatch Alarms](#2-responding-to-cloudwatch-alarms)
3. [Rotating KMS Keys](#3-rotating-kms-keys)
4. [Adding a New Notification Channel](#4-adding-a-new-notification-channel)
5. [Troubleshooting Failed Deployments](#5-troubleshooting-failed-deployments)
6. [Handling Fargate Spot Interruptions](#6-handling-fargate-spot-interruptions)
7. [VPC Endpoint Troubleshooting (Internal Account)](#7-vpc-endpoint-troubleshooting-internal-account)
8. [TLS Certificate Troubleshooting](#8-tls-certificate-troubleshooting)
9. [WAF Troubleshooting](#9-waf-troubleshooting)
10. [Running Resilience Experiments](#10-running-resilience-experiments)
11. [Admin Dashboard Operations](#11-admin-dashboard-operations)

---

## 1. Onboarding a New Application

Use the `odot-app-template` GitHub repository template to bootstrap a new web application with pre-configured CI/CD and infrastructure. No tickets or manual IAM changes are required.

### Prerequisites

- Access to the ODOT GitHub Enterprise organization
- AWS CLI configured with credentials for the target account (via Identity Center SSO)
- Terraform >= 1.5.0 installed
- Platform infrastructure already deployed (VPC, ECS cluster, KMS key, SNS topic exist)

### Steps

**Step 1: Create a new repository from the template**

1. Navigate to the `odot-app-template` repository in GitHub Enterprise.
2. Click **Use this template** → **Create a new repository**.
3. Name the repository following the convention: `odot-{app-name}` (e.g., `odot-permit-portal`).
4. Set visibility to **Internal** (or **Private** for external-facing apps).

**Step 2: Configure Terraform variables**

1. Copy the example variables file:
   ```bash
   cd terraform/
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your application settings:
   ```hcl
   # Application configuration
   app_name       = "permit-portal"    # Unique app identifier (lowercase, hyphens allowed)
   runtime        = "linux"            # "linux" or "windows"
   container_port = 8080               # Port your container listens on
   cpu            = 256                 # CPU units: 256, 512, 1024, 2048, 4096
   memory         = 512                # Memory in MiB

   # Infrastructure references (obtain from platform team or Terraform outputs)
   account_type       = "external"
   stage              = "dev"
   vpc_id             = "vpc-0abc123def456"
   private_subnet_ids = ["subnet-aaa111", "subnet-bbb222"]
   alb_subnet_ids     = ["subnet-ccc333", "subnet-ddd444"]
   cluster_arn        = "arn:aws:ecs:us-east-2:549136075921:cluster/WebHosting-Dev"
   cluster_name       = "WebHosting-Dev"
   kms_key_arn        = "arn:aws:kms:us-east-2:549136075921:key/abc-123-def"
   waf_acl_arn        = "arn:aws:wafv2:us-east-2:549136075921:regional/webacl/odot-external/..."
   sns_topic_arn      = "arn:aws:sns:us-east-2:549136075921:odot-alerts-external"
   ```

3. Configure the S3 backend in `terraform/main.tf`:
   ```hcl
   backend "s3" {
     bucket         = "odot-terraform-state-MGMT-ACCOUNT-ID"
     key            = "apps/permit-portal/terraform.tfstate"
     region         = "us-east-2"
     dynamodb_table = "odot-terraform-locks"
     encrypt        = true
   }
   ```

**Step 3: Provision AWS resources**

```bash
terraform init
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
```

This creates: ECR repository, ECS service, ALB target group, IAM roles, CloudWatch alarms, and auto-scaling policies. Expected completion time: under 15 minutes.

**Step 4: Configure GitHub repository variables**

In your new repository, go to **Settings → Secrets and variables → Actions → Variables** and set:

| Variable | Value |
|---|---|
| `AWS_DEPLOY_ROLE_ARN` | The OIDC role ARN from platform outputs (e.g., `arn:aws:iam::549136075921:role/odot-github-actions-external`) |
| `AWS_REGION` | `us-east-2` |
| `ECR_REPOSITORY` | ECR repository URL from Terraform output |

**Step 5: Push your application code**

1. Update the `Dockerfile` with your application build steps.
2. Push to the `dev` branch to trigger the first CI/CD pipeline run:
   ```bash
   git checkout -b dev
   git push -u origin dev
   ```

**Step 6: Verify deployment**

```bash
# Check ECS service status
aws ecs describe-services \
  --cluster WebHosting-Dev \
  --services permit-portal-dev \
  --region us-east-2

# Check ALB health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --region us-east-2
```

---

## 2. Responding to CloudWatch Alarms

The platform provisions four monitoring alarms per application service. Alarms route to Slack (via AWS Chatbot) and email (for ServiceNow/FortiSIEM).

### Alarm Reference

| Alarm | Threshold | Severity | Escalation |
|---|---|---|---|
| CPU Utilization High | > 80% for 5 min | **Warning** | Platform team on-call |
| Memory Utilization High | > 80% for 5 min | **Warning** | Platform team on-call |
| ALB 5xx Error Rate High | > 1% for 5 min | **Critical** | Application owner + Platform team |
| Task Count Low | < 2 running tasks | **Critical** | Platform team on-call (immediate) |

### 2.1 CPU Utilization High

**Alarm name pattern**: `odot-{app_name}-{stage}-cpu-utilization-high`

**What it means**: Average CPU across the service's tasks exceeds 80% for 5 consecutive minutes. Auto-scaling should already be adding tasks (scale-out triggers at 70% for 3 min).

**Response steps**:

1. Check if auto-scaling is responding:
   ```bash
   aws ecs describe-services \
     --cluster WebHosting-Prod \
     --services myapp-prod \
     --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}' \
     --region us-east-2
   ```

2. Check recent scaling activity:
   ```bash
   aws application-autoscaling describe-scaling-activities \
     --service-namespace ecs \
     --resource-id service/WebHosting-Prod/myapp-prod \
     --region us-east-2
   ```

3. If tasks are at max capacity (50), coordinate with the application owner to:
   - Optimize application performance
   - Increase CPU allocation in the task definition
   - Request a temporary max capacity increase

4. If auto-scaling is not responding, check the scaling policy:
   ```bash
   aws application-autoscaling describe-scaling-policies \
     --service-namespace ecs \
     --resource-id service/WebHosting-Prod/myapp-prod \
     --region us-east-2
   ```

### 2.2 Memory Utilization High

**Alarm name pattern**: `odot-{app_name}-{stage}-memory-utilization-high`

**What it means**: Average memory utilization exceeds 80% for 5 minutes. Risk of OOM kills if memory continues to climb.

**Response steps**:

1. Check for OOM-killed tasks in recent stopped tasks:
   ```bash
   aws ecs list-tasks \
     --cluster WebHosting-Prod \
     --service-name myapp-prod \
     --desired-status STOPPED \
     --region us-east-2
   ```

2. Inspect stopped task reason:
   ```bash
   aws ecs describe-tasks \
     --cluster WebHosting-Prod \
     --tasks <task-arn> \
     --query 'tasks[0].stoppedReason' \
     --region us-east-2
   ```

3. Check CloudWatch logs for memory-related errors:
   ```bash
   aws logs filter-log-events \
     --log-group-name /ecs/myapp/prod \
     --filter-pattern "OutOfMemory OR OOM OR MemoryError" \
     --start-time $(date -d '1 hour ago' +%s000) \
     --region us-east-2
   ```

4. If memory leak is suspected, coordinate with the application owner. Short-term mitigation: increase task memory allocation via Terraform variable update.

### 2.3 ALB 5xx Error Rate High

**Alarm name pattern**: `odot-{app_name}-{stage}-alb-5xx-rate-high`

**What it means**: More than 1% of responses are returning 5xx errors for 5 minutes. This indicates application-level failures.

**Severity**: Critical — impacts end users.

**Response steps**:

1. Check target health:
   ```bash
   aws elbv2 describe-target-health \
     --target-group-arn <target-group-arn> \
     --region us-east-2
   ```

2. Check application logs for errors:
   ```bash
   aws logs filter-log-events \
     --log-group-name /ecs/myapp/prod \
     --filter-pattern "ERROR OR Exception OR 500" \
     --start-time $(date -d '15 minutes ago' +%s000) \
     --region us-east-2
   ```

3. Check if a recent deployment caused the issue:
   ```bash
   aws ecs describe-services \
     --cluster WebHosting-Prod \
     --services myapp-prod \
     --query 'services[0].deployments' \
     --region us-east-2
   ```

4. If a bad deployment is identified, roll back:
   ```bash
   # Get the previous task definition revision
   aws ecs describe-task-definition \
     --task-definition myapp-prod \
     --region us-east-2

   # Force a new deployment with the previous revision
   aws ecs update-service \
     --cluster WebHosting-Prod \
     --service myapp-prod \
     --task-definition myapp-prod:<previous-revision> \
     --force-new-deployment \
     --region us-east-2
   ```

5. Notify the application owner with log excerpts and timeline.

### 2.4 Task Count Low

**Alarm name pattern**: `odot-{app_name}-{stage}-task-count-low`

**What it means**: Fewer than 2 tasks are running. The service is degraded or unavailable.

**Severity**: Critical — immediate response required.

**Response steps**:

1. Check service events for failure reasons:
   ```bash
   aws ecs describe-services \
     --cluster WebHosting-Prod \
     --services myapp-prod \
     --query 'services[0].events[:5]' \
     --region us-east-2
   ```

2. Check for stopped tasks and their stop reasons:
   ```bash
   aws ecs list-tasks \
     --cluster WebHosting-Prod \
     --service-name myapp-prod \
     --desired-status STOPPED \
     --region us-east-2

   # Then describe each stopped task
   aws ecs describe-tasks \
     --cluster WebHosting-Prod \
     --tasks <task-arn> \
     --query 'tasks[0].{reason:stoppedReason,code:stopCode,container:containers[0].reason}' \
     --region us-east-2
   ```

3. Common causes and fixes:
   - **Image pull failure**: Check ECR repository and image tag exist
   - **Health check failure**: Check ALB target group health check path
   - **Resource limits**: Check if the cluster has capacity
   - **Spot interruption** (dev/test): See [Section 6](#6-handling-fargate-spot-interruptions)

4. Force a new deployment if tasks are stuck:
   ```bash
   aws ecs update-service \
     --cluster WebHosting-Prod \
     --service myapp-prod \
     --force-new-deployment \
     --region us-east-2
   ```

### Escalation Path

| Severity | Response Time | Escalation |
|---|---|---|
| Warning | 30 minutes | Platform team on-call engineer |
| Critical | 5 minutes | Platform team on-call + application owner |
| Critical (Prod) | Immediate | Platform team lead + application owner + management notification |

---

## 3. Rotating KMS Keys

The platform uses one KMS Customer Managed Key (CMK) per account with automatic annual rotation enabled (`enable_key_rotation = true`). Under normal operations, no manual rotation is needed.

### Automatic Rotation (Default)

- AWS automatically rotates the key material every year.
- The key ID and ARN remain the same; only the backing key material changes.
- Previously encrypted data remains accessible (AWS retains all previous key versions).
- No action required from the platform team.

### Verifying Rotation Status

```bash
# Check rotation status for the internal account key
aws kms get-key-rotation-status \
  --key-id alias/odot-internal \
  --region us-east-2

# Check rotation status for the external account key
aws kms get-key-rotation-status \
  --key-id alias/odot-external \
  --region us-east-2
```

### Manual Rotation (If Required)

Manual rotation is needed only in exceptional circumstances (e.g., suspected key compromise, compliance audit requirement for immediate rotation).

**Step 1: Create a new KMS key**

```bash
aws kms create-key \
  --description "ODOT internal account CMK - rotated $(date +%Y-%m-%d)" \
  --tags TagKey=Project,TagValue=ODOTWebHosting TagKey=Owner,TagValue=odot-platform-team TagKey=Environment,TagValue=prod \
  --region us-east-2
```

**Step 2: Update the alias to point to the new key**

```bash
aws kms update-alias \
  --alias-name alias/odot-internal \
  --target-key-id <new-key-id> \
  --region us-east-2
```

**Step 3: Update Terraform state**

Update the `modules/security/main.tf` to reference the new key, or import the new key into Terraform state:

```bash
terraform import 'module.security.aws_kms_key.this' <new-key-id>
terraform plan  # Verify no unexpected changes
terraform apply
```

**Step 4: Re-encrypt resources with the new key**

ECR images and CloudWatch logs encrypted with the old key remain readable (AWS retains old key material). New data will use the new key automatically via the alias. For S3 objects, trigger re-encryption:

```bash
aws s3 cp s3://odot-terraform-state-ACCOUNT-ID/ s3://odot-terraform-state-ACCOUNT-ID/ \
  --recursive \
  --sse aws:kms \
  --sse-kms-key-id <new-key-id> \
  --region us-east-2
```

**Step 5: Schedule deletion of the old key (after validation period)**

Wait at least 30 days to confirm no services depend on the old key, then:

```bash
aws kms schedule-key-deletion \
  --key-id <old-key-id> \
  --pending-window-in-days 30 \
  --region us-east-2
```

---

## 4. Adding a New Notification Channel

The platform supports two notification channel types: Slack channels (via AWS Chatbot) and email addresses (via SNS subscriptions).

### 4.1 Adding a New Slack Channel

**Step 1: Get the Slack channel ID**

1. In Slack, right-click the channel name → **View channel details**.
2. Scroll to the bottom and copy the **Channel ID** (e.g., `C0123456789`).

**Step 2: Authorize AWS Chatbot in the Slack workspace** (first time only)

1. Go to the [AWS Chatbot console](https://console.aws.amazon.com/chatbot/).
2. Click **Configure new client** → **Slack**.
3. Authorize the ODOT Slack workspace. Note the **Workspace ID**.

**Step 3: Update Terraform configuration**

Edit the monitoring module variables in the appropriate stack (e.g., `stacks/internal-prod/terraform.tfvars`):

```hcl
slack_workspace_id = "T0123ABCDEF"       # Slack workspace ID
slack_channel_id   = "C0123456789"       # New Slack channel ID
```

**Step 4: Apply the change**

```bash
cd stacks/internal-prod/
terraform init
terraform plan
terraform apply
```

**Step 5: Verify the integration**

Trigger a test notification:

```bash
aws sns publish \
  --topic-arn arn:aws:sns:us-east-2:577881328002:odot-alerts-internal \
  --message "Test notification from ODOT platform team" \
  --subject "Test Alert" \
  --region us-east-2
```

Confirm the message appears in the new Slack channel.

### 4.2 Adding a New Email Subscription

**Step 1: Add the email to the monitoring module**

Edit `stacks/{account}-{stage}/terraform.tfvars`:

```hcl
alert_email = "new-alerts@odot.ohio.gov"
```

**Step 2: Apply the change**

```bash
cd stacks/internal-prod/
terraform plan
terraform apply
```

**Step 3: Confirm the subscription**

The new email address will receive a confirmation email from AWS SNS. The recipient must click the **Confirm subscription** link within 3 days.

**Step 4: Verify**

```bash
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:us-east-2:577881328002:odot-alerts-internal \
  --region us-east-2
```

### 4.3 Adding an Additional Email (Without Replacing Existing)

If you need multiple email endpoints, add a subscription directly via AWS CLI (outside Terraform):

```bash
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-2:577881328002:odot-alerts-internal \
  --protocol email \
  --notification-endpoint additional-team@odot.ohio.gov \
  --region us-east-2
```

The recipient must confirm the subscription via the email link.

---

## 5. Troubleshooting Failed Deployments

The CI/CD pipeline uses GitHub Actions with ECS rolling deployments and a deployment circuit breaker for automatic rollback.

### 5.1 Pipeline Failure — Unit Tests

**Symptom**: The `unit-test` job fails in GitHub Actions.

**Response**:
1. Check the GitHub Actions run log for test failure details.
2. This is an application-level issue — notify the application developer.
3. No infrastructure action needed. The pipeline halts before any AWS interaction.

### 5.2 Pipeline Failure — Security Scan

**Symptom**: The `scan` job fails (Trivy, Inspector, or CodeQL found Critical/High vulnerabilities).

**Response**:
1. Check the GitHub Actions run log for the scan report.
2. Trivy findings include CVE IDs and remediation guidance.
3. The image was NOT pushed to ECR — no deployment occurred.
4. Application developer must update base images or fix vulnerable dependencies.

### 5.3 Pipeline Failure — Docker Build

**Symptom**: The `build-push` job fails.

**Response**:
1. Check the build log for Dockerfile errors.
2. Common causes: missing build dependencies, incorrect base image, syntax errors.
3. Application developer fixes the Dockerfile and re-pushes.

### 5.4 ECS Deployment Failure — Circuit Breaker Rollback

**Symptom**: ECS service shows a deployment with `rolloutState = FAILED` and the service automatically rolled back to the previous task definition.

**Diagnosis**:

```bash
# Check deployment status
aws ecs describe-services \
  --cluster WebHosting-Prod \
  --services myapp-prod \
  --query 'services[0].deployments' \
  --region us-east-2

# Check service events for failure details
aws ecs describe-services \
  --cluster WebHosting-Prod \
  --services myapp-prod \
  --query 'services[0].events[:10]' \
  --region us-east-2
```

**Common causes**:

| Cause | Indicator | Fix |
|---|---|---|
| Health check failure | "service myapp-prod has reached a steady state" never appears | Fix application health endpoint; verify ALB health check path |
| Image pull error | "CannotPullContainerError" in stopped task reason | Verify image exists in ECR; check IAM permissions |
| Container crash | "Essential container exited" | Check CloudWatch logs at `/ecs/myapp/prod` |
| Port conflict | "bind: address already in use" in logs | Verify `container_port` matches application config |
| Resource limits | "OutOfMemoryError" or task killed | Increase `cpu` or `memory` in Terraform variables |

**Recovery**:

```bash
# View logs from the failed task
aws logs get-log-events \
  --log-group-name /ecs/myapp/prod \
  --log-stream-name "ecs/myapp/<task-id>" \
  --region us-east-2

# After fixing the issue, re-push to trigger a new deployment
git push origin prod
```

### 5.5 Manual Rollback

If automatic rollback did not restore service or you need to roll back to a specific version:

```bash
# List recent task definition revisions
aws ecs list-task-definitions \
  --family-prefix myapp-prod \
  --sort DESC \
  --max-items 5 \
  --region us-east-2

# Deploy a specific revision
aws ecs update-service \
  --cluster WebHosting-Prod \
  --service myapp-prod \
  --task-definition myapp-prod:<known-good-revision> \
  --force-new-deployment \
  --region us-east-2

# Monitor the rollback
aws ecs wait services-stable \
  --cluster WebHosting-Prod \
  --services myapp-prod \
  --region us-east-2
```

---

## 6. Handling Fargate Spot Interruptions

Fargate Spot is used in Dev and Test stages for Linux containers to reduce costs. Spot tasks can be interrupted by AWS with a 2-minute warning.

### How Spot Interruptions Work

1. AWS sends a `SIGTERM` to the task container.
2. The application has 30 seconds (`stopTimeout`) to gracefully shut down (drain connections, flush buffers).
3. After 30 seconds, AWS sends `SIGKILL` to force-stop the container.
4. ECS automatically launches a replacement task (minimum task count = 2 ensures availability).

### Identifying Spot Interruptions

```bash
# Check for tasks stopped due to Spot interruption
aws ecs list-tasks \
  --cluster WebHosting-Dev \
  --service-name myapp-dev \
  --desired-status STOPPED \
  --region us-east-2

aws ecs describe-tasks \
  --cluster WebHosting-Dev \
  --tasks <task-arn> \
  --query 'tasks[0].{reason:stoppedReason,code:stopCode}' \
  --region us-east-2
```

A Spot interruption shows `stopCode: "SpotInterruption"` or `stoppedReason` containing "host task was stopped".

### When to Take Action

**No action needed** (normal operation):
- The `task-count-low` alarm fires briefly and resolves within 2–3 minutes as ECS launches replacement tasks.
- This is expected behavior in Dev/Test environments.

**Action needed** (repeated interruptions):
- If Spot interruptions are frequent and causing development disruption, temporarily switch to on-demand Fargate:

```bash
# Temporary: force on-demand capacity
aws ecs update-service \
  --cluster WebHosting-Dev \
  --service myapp-dev \
  --capacity-provider-strategy capacityProvider=FARGATE,weight=1,base=0 \
  --force-new-deployment \
  --region us-east-2
```

To revert to Spot (via Terraform):
```bash
cd stacks/internal-dev/
terraform apply  # Restores the Terraform-defined capacity provider strategy
```

### Application Requirements for Spot Readiness

Applications running on Fargate Spot must:
- Handle `SIGTERM` gracefully (drain in-flight requests within 30 seconds)
- Not rely on local filesystem state (root filesystem is read-only)
- Be stateless or use external state stores (DynamoDB, ElastiCache, S3)

If an application cannot tolerate interruptions, set `runtime = "windows"` (which forces on-demand Fargate) or request a Terraform variable override to disable Spot for that specific service.

---

## Appendix: Useful Commands

### Check overall cluster health

```bash
aws ecs describe-clusters \
  --clusters WebHosting-Dev WebHosting-Test WebHosting-Prod \
  --include STATISTICS \
  --region us-east-2
```

### List all services in a cluster

```bash
aws ecs list-services \
  --cluster WebHosting-Prod \
  --region us-east-2
```

### View active CloudWatch alarms

```bash
aws cloudwatch describe-alarms \
  --state-value ALARM \
  --alarm-name-prefix "odot-" \
  --region us-east-2
```

### Check SNS topic subscriptions

```bash
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:us-east-2:577881328002:odot-alerts-internal \
  --region us-east-2
```

### View recent ECR images

```bash
aws ecr describe-images \
  --repository-name odot-myapp-internal \
  --query 'imageDetails | sort_by(@, &imagePushedAt) | [-5:]' \
  --region us-east-2
```


---

## 7. VPC Endpoint Troubleshooting (Internal Account)

Internal-account VPCs use VPC interface endpoints for all AWS service access. If tasks fail to launch with `CannotPullContainerError`, the endpoints may be misconfigured.

### Symptoms

- ECS tasks stuck in `PROVISIONING` state
- Stopped task reason: `CannotPullContainerError` or `ResourceInitializationError`
- CloudWatch logs not appearing (log delivery also uses endpoints)

### Diagnosis

```bash
# List all VPC endpoints in the internal VPC
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --query "VpcEndpoints[].{Service:ServiceName,State:State,DNS:DnsEntries[0].DnsName}" \
  --region us-east-2
```

All 7 interface endpoints + 1 S3 gateway should show `State: available`.

### Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| Endpoint state `pending` | Recently created, still provisioning | Wait 2–5 minutes |
| Endpoint state `failed` | Subnet or SG misconfiguration | Check subnet IDs and security group |
| Image pull timeout | Endpoint SG doesn't allow 443 from VPC CIDR | Verify SG allows inbound 443 from VPC CIDR |
| S3 layer download fails | S3 gateway endpoint not associated with route tables | Check route table associations |
| DNS resolution fails | `private_dns_enabled` not set | Verify endpoint has private DNS enabled |

### Verify Endpoint Connectivity (from within VPC)

If you have ECS Exec or a bastion:

```bash
# Test ECR API endpoint resolution
nslookup ecr.us-east-2.amazonaws.com
# Should resolve to a private IP (10.x.x.x), NOT a public IP

# Test S3 connectivity
aws s3 ls --region us-east-2
```

---

## 8. TLS Certificate Troubleshooting

All ALBs use ACM certificates for HTTPS. Certificates are created via DNS validation.

### Certificate Not Validating

**Symptom**: `terraform apply` hangs at `aws_acm_certificate_validation` or the cert shows `PENDING_VALIDATION`.

**Diagnosis**:

```bash
aws acm describe-certificate \
  --certificate-arn <cert-arn> \
  --query "Certificate.{Status:Status,ValidationMethod:DomainValidationOptions[0].ValidationMethod,CNAME:DomainValidationOptions[0].ResourceRecord}" \
  --region us-east-2
```

**Common causes**:
- Route 53 hosted zone doesn't exist or isn't delegated
- DNS validation CNAME record wasn't created (check Route 53 for the `_acme-challenge` record)
- Wrong hosted zone ID in Terraform variables

**Fix**: Verify the hosted zone is delegated (NS records at the parent match), then re-run `terraform apply`.

### Certificate Expiring

ACM certificates auto-renew if DNS validation records are still in place. If renewal fails:

```bash
aws acm describe-certificate \
  --certificate-arn <cert-arn> \
  --query "Certificate.RenewalSummary" \
  --region us-east-2
```

Ensure the DNS validation CNAME record still exists in Route 53.

---

## 9. WAF Troubleshooting

External ALBs are protected by WAF with managed rule groups. Occasionally legitimate traffic may be blocked.

### Identifying False Positives

```bash
# Check WAF sampled requests (last 3 hours)
aws wafv2 get-sampled-requests \
  --web-acl-arn <waf-acl-arn> \
  --rule-metric-name AWS-AWSManagedRulesCommonRuleSet \
  --scope REGIONAL \
  --time-window StartTime=$(date -d '3 hours ago' +%s),EndTime=$(date +%s) \
  --max-items 10 \
  --region us-east-2
```

### Rate Limiting

The rate-based rule blocks IPs exceeding 2,000 requests per 5 minutes. If a legitimate client is blocked:

```bash
# Check if an IP is currently rate-limited
aws wafv2 get-rate-based-statement-managed-keys \
  --web-acl-arn <waf-acl-arn> \
  --rule-name odot-rate-limit \
  --scope REGIONAL \
  --region us-east-2
```

Rate-limited IPs are automatically unblocked after 5 minutes of reduced traffic.

### Temporarily Disabling a Rule (Emergency)

If a managed rule is causing widespread false positives:

1. Set the rule to `COUNT` mode (logs but doesn't block) via the AWS console or CLI
2. Investigate the pattern
3. Add an exclusion rule or adjust the rule action
4. Re-enable `BLOCK` mode after resolution

---

## 10. Running Resilience Experiments

AWS Fault Injection Simulator (FIS) experiments validate platform recovery. Run these periodically (monthly recommended) or before major releases.

### Available Experiments

| Experiment | What It Does | Expected Recovery |
|---|---|---|
| `fis-stop-tasks-single-az` | Stops 50% of tasks in one AZ | ECS replaces tasks within 5 minutes |
| `fis-bad-deployment` | Validates circuit breaker rollback | ECS rolls back within 5 minutes |

### Running an Experiment

```bash
# List available experiment templates
aws fis list-experiment-templates \
  --query "experimentTemplates[].{Id:id,Description:description}" \
  --region us-east-2

# Start an experiment
aws fis start-experiment \
  --experiment-template-id <template-id> \
  --region us-east-2

# Monitor the experiment
aws fis get-experiment \
  --id <experiment-id> \
  --query "experiment.{State:state.status,Actions:actions}" \
  --region us-east-2
```

### Safety

- Experiments have **stop conditions** wired to CloudWatch alarms — if availability drops below a floor, the experiment halts automatically
- Always run experiments in **Dev or Test first** before Prod
- Notify the team before running Prod experiments

---

## 11. Admin Dashboard Operations

### User Management

Users are managed via Okta groups. No AWS console access is needed.

**Grant access**: Add the user to `ODOT-Web-Developers` (Dev/Test) or `ODOT-Web-Admins` (all stages) in Okta.

**Revoke access**: Remove the user from both Okta groups. Their Cognito session expires within 1 hour (token validity).

**Emergency revocation**: Sign the user out of all sessions via Cognito:

```bash
aws cognito-idp admin-user-global-sign-out \
  --user-pool-id <pool-id> \
  --username <user-sub> \
  --region us-east-2
```

### Reviewing Audit Logs

All dashboard actions are logged to DynamoDB (`odot-dashboard-audit-{stage}`):

```bash
# Query recent actions for an app
aws dynamodb query \
  --table-name odot-dashboard-audit-prod \
  --key-condition-expression "pk = :pk" \
  --expression-attribute-values '{":pk":{"S":"fleet-tracker#prod"}}' \
  --scan-index-forward false \
  --limit 10 \
  --region us-east-2

# Query actions by a specific user
aws dynamodb query \
  --table-name odot-dashboard-audit-prod \
  --index-name user-index \
  --key-condition-expression "userId = :uid" \
  --expression-attribute-values '{":uid":{"S":"user-sub-id"}}' \
  --scan-index-forward false \
  --limit 10 \
  --region us-east-2
```

### Audit Archive (Immutable)

Daily exports go to `odot-dashboard-audit-archive-{stage}` (S3 with Object Lock). These cannot be deleted or modified for 365 days.

```bash
# List recent audit exports
aws s3 ls s3://odot-dashboard-audit-archive-prod/audit/ --region us-east-2
```

### Dashboard Not Loading

1. Check ECS service health: `aws ecs describe-services --cluster WebHosting-Prod --services dashboard-prod`
2. Check Cognito: `aws cognito-idp describe-user-pool --user-pool-id <id>`
3. Check VPC endpoints (dashboard runs in internal account — needs endpoints for Cognito, ECS, CloudWatch)
4. Check CloudWatch logs: `aws logs tail /ecs/dashboard/prod --follow`
