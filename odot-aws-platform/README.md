# ODOT AWS Web Hosting Platform

Infrastructure-as-Code repository for the Ohio Department of Transportation (ODOT) Web Application Hosting environment on AWS. This platform provisions a secure, fully serverless container hosting environment across two dedicated AWS accounts using ECS Fargate, with automated CI/CD via GitHub Enterprise Actions and comprehensive observability through CloudWatch and Slack.

---

## Overview

The platform hosts containerized web applications across six isolated environments (Dev, Test, Prod × two accounts). Internal workloads are accessible only via Client VPN or Direct Connect; external workloads are public-facing with WAF and Shield protection.

Key characteristics:

- **Fargate-only compute** — no EC2 instances to manage
- **Zero-egress internal VPCs** — VPC endpoints for all AWS service access, no NAT/IGW
- **HTTPS everywhere** — TLS 1.3 on all ALBs with automatic ACM certificate management
- **WAF with managed rules** — OWASP Top 10, SQLi, rate limiting on all external ALBs
- **Module-per-concern** — reusable Terraform modules shared across all six stacks
- **OIDC authentication** — GitHub Actions authenticates to AWS via federation (no stored credentials)
- **Policy-as-code** — tfsec + OPA/Conftest gate on every platform PR
- **NIST 800-53 aligned** — Security Hub with both FSBP and NIST standards
- **S3 + DynamoDB backend** — remote state with locking and versioning (split per account)

---

## Architecture

### Account Structure

```
AWS Organizations (Management Account)
└── OU: ODOT-Web
    ├── DOT-Web-Internal (577881328002)   ← private workloads
    │   ├── VPC: internal-dev   (us-east-2)
    │   ├── VPC: internal-test  (us-east-2)
    │   └── VPC: internal-prod  (us-east-2)
    └── DOT-Web-External (549136075921)   ← public workloads
        ├── VPC: external-dev   (us-east-2)
        ├── VPC: external-test  (us-east-2)
        └── VPC: external-prod  (us-east-2)
```

### Network Topology

- **Internal Account**: Private subnets only (no IGW, no NAT). AWS service access via VPC interface endpoints (ECR, Logs, Secrets Manager, SSM, STS) and S3 gateway endpoint. Traffic enters via Client VPN or Direct Connect to internal ALBs.
- **External Account**: Public subnets (IGW-attached) for ALBs + private subnets (NAT gateway) for ECS tasks. All ALBs protected by WAF Web ACL (managed rules + rate limiting) and Shield Standard. All traffic encrypted via TLS 1.3.

### Compute

Each account-stage combination has one ECS Fargate cluster:

| Cluster | Capacity Strategy |
|---------|-------------------|
| `WebHosting-Dev` | Fargate Spot (cost savings) |
| `WebHosting-Test` | Fargate Spot (cost savings) |
| `WebHosting-Prod` | Fargate On-Demand (reliability) |

All clusters have Container Insights enabled. Services auto-scale between 2–50 tasks based on CPU/memory utilization.

---

## Repository Structure

```
odot-aws-platform/
├── modules/
│   ├── networking/         # VPC, subnets, route tables, VPC endpoints (internal)
│   ├── ecs-cluster/        # ECS cluster, capacity providers, Container Insights
│   ├── app-service/        # ECS service, task def, ALB (HTTPS), ECR, auto-scaling, alarms
│   ├── security/           # GuardDuty, Security Hub (FSBP + NIST), Config, Macie, KMS, SCPs
│   ├── monitoring/         # CloudWatch dashboards, SNS, Chatbot, Budgets, EventBridge
│   ├── oidc/               # GitHub OIDC provider + IAM roles
│   ├── admin-dashboard/    # Cognito (Okta), DynamoDB audit, IAM roles, WAF IP set, audit archive
│   └── resilience/         # AWS FIS experiment templates for fault injection
├── stacks/
│   ├── internal-dev/       # Stack config for Internal Dev
│   ├── internal-test/      # Stack config for Internal Test
│   ├── internal-prod/      # Stack config for Internal Prod
│   ├── external-dev/       # Stack config for External Dev
│   ├── external-test/      # Stack config for External Test
│   ├── external-prod/      # Stack config for External Prod
│   └── management/         # Management account (tag policies, SCPs)
├── policy/
│   ├── tags.rego           # OPA: required tags on all resources
│   ├── security_groups.rego # OPA: no open ingress except ALB 443
│   └── encryption.rego     # OPA: all storage encrypted
├── scripts/
│   ├── bootstrap-backend.sh   # One-time backend setup (S3 + DynamoDB)
│   ├── configure-backend.sh   # Replace MGMT_ACCOUNT_ID in all backend.tf
│   ├── deploy-platform.sh     # Deploy all stacks in dependency order
│   ├── collect-stack-outputs.sh # Collect Terraform outputs to JSON
│   ├── onboard-app.sh         # Automate full app onboarding
│   ├── verify-prerequisites.sh # Validate all prerequisites
│   ├── smoke-test.sh          # Post-deployment validation
│   ├── scanner-gate.go        # Vulnerability severity gate logic
│   └── image-tag.go           # Docker image tag generation
├── test/                   # 80+ Go property and unit tests (Terratest + rapid)
├── docs/
│   ├── architecture/       # Network, CI/CD, ECS, and dashboard diagrams
│   ├── compliance/         # NIST 800-53 control mapping
│   └── runbook.md          # Operational procedures
├── .github/workflows/
│   └── platform-ci.yml    # tfsec + OPA + Go tests on every PR
├── backend.tf              # Root backend config (internal account state)
└── versions.tf             # Required Terraform and provider versions
```

---

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Go](https://go.dev/dl/) >= 1.21 (for running tests)
- AWS IAM Identity Center (SSO) profiles configured for both accounts (see below)
- Access to the ODOT GitHub Enterprise organization

---

## Getting Started

### 0. Configure AWS SSO Profiles

Set up named CLI profiles for each account:

```bash
aws configure sso
# SSO session name: odot-sso
# SSO start URL: https://your-sso-url.awsapps.com/start
# SSO region: us-east-2
# Select account 577881328002 → profile name: odot-internal

aws configure sso --profile odot-external
# Same SSO session, select account 549136075921 → profile name: odot-external
```

Verify:
```bash
aws sts get-caller-identity --profile odot-internal
aws sts get-caller-identity --profile odot-external
```

### 1. Bootstrap the Terraform Backend (Both Accounts)

Each account hosts its own state bucket and lock table:

```bash
# Internal account
export AWS_PROFILE=odot-internal
./scripts/bootstrap-backend.sh 577881328002

# External account
export AWS_PROFILE=odot-external
./scripts/bootstrap-backend.sh 549136075921
```

Each creates:
- S3 bucket: `odot-terraform-state-<ACCOUNT_ID>` (versioned, encrypted, public access blocked)
- DynamoDB table: `odot-terraform-locks` (partition key: `LockID`)

### 2. Update Backend Configuration (If Starting Fresh)

Backend.tf files are pre-configured with the correct account IDs. If you need to reconfigure from a fresh clone:

```bash
./scripts/configure-backend.sh --internal 577881328002 --external 549136075921
```

This routes internal stacks to the internal account bucket and external stacks to the external account bucket.

### 3. Initialize and Deploy a Stack

Navigate to the desired stack directory and run:

```bash
export AWS_PROFILE=odot-internal   # or odot-external for external stacks
cd stacks/internal-dev

terraform init
terraform plan
terraform apply
```

Repeat for each stack you want to deploy.

---

## Module Reference

### `modules/networking`

Provisions a VPC and all subnet/routing resources for one account-stage combination.

| Input | Type | Description |
|-------|------|-------------|
| `account_type` | `string` | `"internal"` or `"external"` |
| `stage` | `string` | `"dev"`, `"test"`, or `"prod"` |
| `vpc_cidr` | `string` | CIDR block for the VPC |
| `availability_zones` | `list(string)` | Minimum 2 AZs |
| `tags` | `map(string)` | Must include `Environment`, `Project`, `Owner` |

**Outputs**: `vpc_id`, `private_subnet_ids`, `public_subnet_ids`, `vpc_cidr_block`

### `modules/ecs-cluster`

Provisions one ECS cluster with Fargate capacity providers and Container Insights.

| Input | Type | Description |
|-------|------|-------------|
| `cluster_name` | `string` | e.g., `WebHosting-Prod` |
| `stage` | `string` | Controls Spot vs on-demand strategy |
| `tags` | `map(string)` | Resource tags |

**Outputs**: `cluster_arn`, `cluster_name`

### `modules/app-service`

Provisions all per-application resources: ECR repo, ECS task definition, ECS service, ALB + target group, auto-scaling policies, CloudWatch alarms, and IAM roles.

| Input | Type | Description |
|-------|------|-------------|
| `app_name` | `string` | Application identifier |
| `account_type` | `string` | `"internal"` or `"external"` |
| `stage` | `string` | Deployment stage |
| `runtime` | `string` | `"linux"` or `"windows"` |
| `container_port` | `number` | Port the container listens on |
| `cpu` | `number` | Task CPU units (256–4096) |
| `memory` | `number` | Task memory in MiB |
| `cluster_arn` | `string` | Target ECS cluster |
| `private_subnet_ids` | `list(string)` | Subnets for ECS tasks |
| `alb_subnet_ids` | `list(string)` | Subnets for ALB |
| `vpc_id` | `string` | VPC for security groups |
| `kms_key_arn` | `string` | KMS key for encryption |
| `waf_acl_arn` | `string` | WAF ACL ARN (required for external) |
| `sns_topic_arn` | `string` | SNS topic for alarm notifications |
| `tags` | `map(string)` | Resource tags |

**Outputs**: `ecr_repository_url`, `alb_dns_name`, `ecs_service_name`, `task_definition_arn`

### `modules/security`

Provisions account-wide security services: GuardDuty, Security Hub, Config, Macie, KMS keys, and SCPs.

Services that are already enabled by AWS Organizations can be skipped via input variables.

| Input | Type | Description |
|-------|------|-------------|
| `account_type` | `string` | `"internal"` or `"external"` |
| `account_id` | `string` | AWS account ID |
| `org_id` | `string` | AWS Organizations ID |
| `enable_guardduty` | `bool` | Set `false` if org-managed (default: `true`) |
| `enable_securityhub` | `bool` | Set `false` if org-managed (default: `true`) |
| `enable_config` | `bool` | Set `false` if org-managed (default: `true`) |
| `enable_macie` | `bool` | Set `false` if org-managed (default: `true`) |
| `tags` | `map(string)` | Must include `Environment`, `Project`, `Owner` |

**Outputs**: `kms_key_arn`, `kms_key_id`, `guardduty_detector_id`

### `modules/monitoring`

Provisions CloudWatch dashboards, SNS topics, AWS Chatbot Slack integrations, and AWS Budgets.

Slack/Chatbot resources are **conditional** — they are only created when a valid (non-placeholder) `slack_workspace_id` is provided. The Slack workspace must be manually authorized in the AWS Chatbot console before Terraform can create the channel configuration.

| Input | Type | Description |
|-------|------|-------------|
| `account_type` | `string` | `"internal"` or `"external"` |
| `stage` | `string` | Deployment stage |
| `slack_workspace_id` | `string` | Slack workspace ID (empty or `T0000...` = skip Chatbot) |
| `slack_channel_id` | `string` | Slack channel ID |
| `alert_email` | `string` | Email for ServiceNow/FortiSIEM |
| `budget_limit_usd` | `number` | Monthly budget limit |
| `tags` | `map(string)` | Resource tags |

**Outputs**: `sns_topic_arn`, `dashboard_name`

### `modules/oidc`

Establishes the GitHub OIDC identity provider and IAM roles for GitHub Actions.

| Input | Type | Description |
|-------|------|-------------|
| `github_org` | `string` | GitHub Enterprise organization |
| `github_repos` | `list(string)` | Repositories allowed to assume the role |
| `account_id` | `string` | AWS account ID |
| `tags` | `map(string)` | Resource tags |

**Outputs**: `github_actions_role_arn`

---

## Stack Deployment

Each stack in `stacks/` represents one account-stage combination with its own Terraform state file. State is stored in the same account the stack deploys to:

| Stack | Account | Stage | State Bucket | State Key |
|-------|---------|-------|-------------|-----------|
| `stacks/internal-dev/` | DOT-Web-Internal (577881328002) | Dev | `odot-terraform-state-577881328002` | `internal-dev/terraform.tfstate` |
| `stacks/internal-test/` | DOT-Web-Internal (577881328002) | Test | `odot-terraform-state-577881328002` | `internal-test/terraform.tfstate` |
| `stacks/internal-prod/` | DOT-Web-Internal (577881328002) | Prod | `odot-terraform-state-577881328002` | `internal-prod/terraform.tfstate` |
| `stacks/external-dev/` | DOT-Web-External (549136075921) | Dev | `odot-terraform-state-549136075921` | `external-dev/terraform.tfstate` |
| `stacks/external-test/` | DOT-Web-External (549136075921) | Test | `odot-terraform-state-549136075921` | `external-test/terraform.tfstate` |
| `stacks/external-prod/` | DOT-Web-External (549136075921) | Prod | `odot-terraform-state-549136075921` | `external-prod/terraform.tfstate` |

### Deploy a Stack

```bash
cd stacks/<stack-name>

# Set the correct profile for the target account
export AWS_PROFILE=odot-internal   # For internal-* stacks
# export AWS_PROFILE=odot-external # For external-* stacks

# Initialize providers and backend
terraform init

# Preview changes
terraform plan

# Apply changes
terraform apply

# Tear down all resources in this stack
terraform destroy
```

### Deploy All Stacks

Deploy stacks in order — internal first, then external. Switch profiles between account boundaries:

```bash
# Internal stacks
export AWS_PROFILE=odot-internal
for stack in internal-dev internal-test internal-prod; do
  cd stacks/$stack
  terraform init
  terraform apply -auto-approve
  cd ../..
done

# External stacks
export AWS_PROFILE=odot-external
for stack in external-dev external-test external-prod; do
  cd stacks/$stack
  terraform init
  terraform apply -auto-approve
  cd ../..
done
```

> **Warning**: Use `-auto-approve` only in automated pipelines or non-production environments. Always review `terraform plan` output before applying to production.

---

## Testing

Tests are written in Go using [Terratest](https://terratest.gruntwork.io/) and [rapid](https://github.com/flyingmutant/rapid) for property-based testing.

### Run All Tests

```bash
cd test
go test ./... -v -timeout 30m
```

### Run a Specific Test

```bash
cd test
go test -run TestStateKeysAreUnique -v
```

### Test Structure

| Test File | Property | What It Validates |
|-----------|----------|-------------------|
| `module_tagging_test.go` | P1: Resource tagging | All resources carry `Environment`, `Project`, `Owner` tags |
| `state_key_test.go` | P9: Unique state keys | Each stack has a distinct state key |

Tests operate on `terraform plan` JSON output — no AWS credentials are required to run them.

---

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/bootstrap-backend.sh` | One-time setup of S3 state bucket and DynamoDB lock table (run per account) |
| `scripts/configure-backend.sh` | Replace MGMT_ACCOUNT_ID placeholder in all backend.tf files (supports split-account mode) |
| `scripts/deploy-platform.sh` | Deploy all platform stacks in correct dependency order |
| `scripts/collect-stack-outputs.sh` | Collect Terraform outputs from all stacks into one JSON file |
| `scripts/onboard-app.sh` | Automate full application onboarding (repo, tfvars, GitHub vars, branches) |
| `scripts/verify-prerequisites.sh` | Validate all deployment prerequisites are in place |
| `scripts/scanner-gate.go` | Evaluates Trivy/Inspector scan results; returns FAIL on Critical/High findings |
| `scripts/image-tag.go` | Generates Docker image tags from commit SHA and branch name |

---

## Current Deployment Status (Testing)

The platform is currently deployed for testing using a personal GitHub account. This section documents the temporary configuration that will change when migrating to enterprise.

| Setting | Current (Testing) | Production (Future) |
|---------|-------------------|---------------------|
| GitHub org | `ftvizsla` | ODOT GitHub Enterprise org |
| Platform repo | `ftvizsla/odot-aws-platform` | `ODOT-GitHub-Org/odot-aws-platform` |
| App template repo | `ftvizsla/odot-app-template` | `ODOT-GitHub-Org/odot-app-template` |
| Slack workspace | `T0B72DR9L5U` (demo) | Enterprise Slack workspace |
| Slack channel | `C0B74FW9W7L` (demo) | `#aws-alerts-internal` / `#aws-alerts-external` |
| Environment protection | None (GitHub Free) | Required reviewers on `production` |
| OIDC trust | `repo:ftvizsla/*` | `repo:ODOT-GitHub-Org/*` |

### Deployed Stacks

| Stack | Status | Notes |
|-------|--------|-------|
| `internal-dev` | ✅ Deployed | VPC (private only, VPC endpoints), ECS, KMS, monitoring, OIDC |
| `internal-test` | ✅ Deployed | VPC (private only, VPC endpoints), ECS cluster |
| `internal-prod` | ✅ Deployed | VPC (private only, VPC endpoints), ECS cluster (Fargate On-Demand) |
| `external-dev` | ✅ Deployed | VPC (public + private, IGW, NAT), ECS, KMS, monitoring, OIDC |
| `external-test` | ✅ Deployed | VPC (public + private, IGW, NAT), ECS cluster |
| `external-prod` | ✅ Deployed | VPC (public + private, IGW, NAT), ECS cluster (Fargate On-Demand) |

### Deployed Applications

| App | Account | Stage | ECS Service | ALB | URL |
|-----|---------|-------|-------------|-----|-----|
| `traffic-dash` | External | Dev | `traffic-dash-dev` | ✅ (HTTP) | [Live Demo](http://odot-traffic-dash-dev-alb-398935479.us-east-2.elb.amazonaws.com) |

### Security Services (Org-Managed)

These services are enabled at the AWS Organization level and are NOT managed by Terraform in this repo:

- GuardDuty, Security Hub, AWS Config, Macie

The security module creates only the **KMS CMK** (`alias/odot-internal`) when `enable_*` flags are `false`.

---

## Contributing

### Adding a New Application

Use the [odot-app-template](../odot-app-template/) repository template to bootstrap a new application. See the template's README for onboarding instructions.

### Modifying Platform Infrastructure

1. Create a feature branch
2. Make changes to the relevant module(s) in `modules/`
3. Run tests: `cd test && go test ./... -v`
4. Run `terraform plan` in the affected stack(s) to preview changes
5. Open a pull request for review
6. After approval, apply changes to non-prod stacks first, then prod

### Naming Conventions

| Resource Type | Pattern | Example |
|---------------|---------|---------|
| ECS Cluster | `WebHosting-{Stage}` | `WebHosting-Prod` |
| VPC | `odot-{account_type}-{stage}` | `odot-internal-prod` |
| ECR Repository | `odot-{app_name}-{account_type}` | `odot-myapp-internal` |
| CloudWatch Log Group | `/ecs/{app_name}/{stage}` | `/ecs/myapp/prod` |
| SNS Topic | `odot-alerts-{account_type}` | `odot-alerts-external` |
| KMS Key Alias | `alias/odot-{account_type}` | `alias/odot-internal` |

### Required Tags

All resources must include:

| Tag | Value |
|-----|-------|
| `Environment` | `dev` / `test` / `prod` |
| `Project` | `ODOTWebHosting` |
| `Owner` | `odot-platform-team` (overridable) |
