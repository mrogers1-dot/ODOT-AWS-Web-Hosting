# ODOT AWS Web Hosting — Deployment Prerequisites

This document covers every step required to take the ODOT AWS Web Hosting platform from a fresh clone to a fully deployed application. Use it as a checklist — complete each section in order before deploying.

---

## Automation Scripts

Most manual steps in this guide have been automated. Here's a quick reference:

| Script | Replaces Manual Step | Usage |
|--------|---------------------|-------|
| `scripts/bootstrap-backend.sh` | S3 bucket + DynamoDB table creation | `./scripts/bootstrap-backend.sh <ACCOUNT_ID>` (run per account) |
| `scripts/configure-backend.sh` | Find/replace MGMT_ACCOUNT_ID in all backend.tf | `./scripts/configure-backend.sh --internal 577881328002 --external 549136075921` |
| `scripts/deploy-platform.sh` | Deploying stacks one-by-one in order | `./scripts/deploy-platform.sh [stack-filter]` |
| `scripts/collect-stack-outputs.sh` | Manually copying Terraform outputs | `./scripts/collect-stack-outputs.sh` |
| `scripts/onboard-app.sh` | Repo creation, tfvars, GitHub vars, branches | `./scripts/onboard-app.sh --app-name ... --account-type ... --github-org ...` |
| `scripts/verify-prerequisites.sh` | Manually checking each prerequisite | `./scripts/verify-prerequisites.sh --app-name ... --account-type ... --stage ... --github-org ...` |

**Fastest path (after AWS accounts exist):**

```bash
# 1. Configure SSO profiles
aws configure sso   # Set up odot-internal profile
aws configure sso --profile odot-external   # Set up odot-external profile

# 2. Bootstrap backend (both accounts)
export AWS_PROFILE=odot-internal
./scripts/bootstrap-backend.sh 577881328002

export AWS_PROFILE=odot-external
./scripts/bootstrap-backend.sh 549136075921

# 3. Configure all backend.tf files (split-account mode)
./scripts/configure-backend.sh --internal 577881328002 --external 549136075921

# 4. Deploy all platform stacks
export AWS_PROFILE=odot-internal
./scripts/deploy-platform.sh internal

export AWS_PROFILE=odot-external
./scripts/deploy-platform.sh external

# 5. Collect outputs for app teams
./scripts/collect-stack-outputs.sh

# 6. Onboard a new application
./scripts/onboard-app.sh \
  --app-name "fleet-tracker" \
  --account-type "internal" \
  --github-org "ODOT-GitHub-Org"

# 7. Verify everything is ready
./scripts/verify-prerequisites.sh \
  --app-name "fleet-tracker" \
  --account-type "internal" \
  --stage "dev" \
  --github-org "ODOT-GitHub-Org"
```

---

## Table of Contents

- [1. Local Tooling](#1-local-tooling)
- [2. AWS Account Setup](#2-aws-account-setup)
- [3. Terraform Backend Bootstrap](#3-terraform-backend-bootstrap)
- [4. GitHub Repository Setup](#4-github-repository-setup)
- [5. GitHub OIDC Federation (AWS ↔ GitHub)](#5-github-oidc-federation-aws--github)
- [6. GitHub Repository Variables and Secrets](#6-github-repository-variables-and-secrets)
- [7. GitHub Environments and Protection Rules](#7-github-environments-and-protection-rules)
- [7.5. Slack / AWS Chatbot Authorization](#75-slack--aws-chatbot-authorization)
- [8. Platform Infrastructure Deployment](#8-platform-infrastructure-deployment)
- [9. Application Onboarding](#9-application-onboarding)
- [10. Verification Checklist](#10-verification-checklist)

---

## 1. Local Tooling

Install these tools on your development machine before proceeding.

| Tool | Minimum Version | Purpose |
|------|-----------------|---------|
| [Terraform](https://www.terraform.io/downloads) | 1.5.0 | Infrastructure provisioning |
| [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | 2.x | AWS interaction and debugging |
| [Docker](https://docs.docker.com/get-docker/) | 20.x | Local container builds and testing |
| [Go](https://go.dev/dl/) | 1.21 | Running platform tests (Terratest) |
| [Git](https://git-scm.com/) | 2.x | Version control |
| [Node.js](https://nodejs.org/) | 20.x | If using CDK or Node-based apps |

### Verify Installation

```bash
terraform --version   # >= 1.5.0
aws --version         # aws-cli/2.x.x
docker --version      # >= 20.x
go version            # >= 1.21
git --version         # >= 2.x
```

---

## 2. AWS Account Setup

The platform uses two dedicated AWS accounts under an AWS Organization.

### Required Accounts

| Account | Account ID | Purpose |
|---------|-----------|---------|
| DOT-Web-Internal | 577881328002 | Private/corporate workloads (VPN/Direct Connect access only) |
| DOT-Web-External | 549136075921 | Public-facing workloads (internet-accessible via ALB + WAF) |

### Prerequisites in Each Account

Complete these steps in **both** the Internal and External accounts:

- [ ] **IAM Identity Center (SSO) access** configured for your team
- [ ] **Service-linked roles** exist for ECS, Application Auto Scaling, and Elastic Load Balancing
  ```bash
  aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com
  aws iam create-service-linked-role --aws-service-name elasticloadbalancing.amazonaws.com
  ```
- [ ] **AWS Region** set to `us-east-2` (Ohio) — all resources deploy here
- [ ] **Resource quotas** reviewed for ECS tasks, ALBs, and VPCs (request increases if needed)

### IAM Identity Center (SSO) Setup

IAM Identity Center is already enabled at the AWS Organization level. Each team member authenticates via the SSO portal and receives temporary credentials — no long-lived access keys are stored locally.

**Setting up your local CLI profiles:**

```bash
aws configure sso
```

When prompted, provide:

| Prompt | Internal Account | External Account |
|--------|-----------------|-----------------|
| SSO session name | `odot-sso` | `odot-sso` |
| SSO start URL | Your org's SSO start URL | Same |
| SSO region | `us-east-2` | `us-east-2` |
| Account | `577881328002` (DOT-Web-Internal) | `549136075921` (DOT-Web-External) |
| Role | Your assigned permission set | Your assigned permission set |
| CLI default region | `us-east-2` | `us-east-2` |
| CLI default output | `json` | `json` |
| Profile name | `odot-internal` | `odot-external` |

After configuration, your `~/.aws/config` will contain:

```ini
[profile odot-internal]
sso_start_url = https://your-sso-url.awsapps.com/start
sso_region = us-east-2
sso_account_id = 577881328002
sso_role_name = YourPermissionSetName
region = us-east-2

[profile odot-external]
sso_start_url = https://your-sso-url.awsapps.com/start
sso_region = us-east-2
sso_account_id = 549136075921
sso_role_name = YourPermissionSetName
region = us-east-2
```

**Logging in:**

```bash
aws sso login --profile odot-internal
aws sso login --profile odot-external
```

**Verifying access:**

```bash
aws sts get-caller-identity --profile odot-internal
# Should show Account: 577881328002

aws sts get-caller-identity --profile odot-external
# Should show Account: 549136075921
```

**Using profiles with Terraform:**

```bash
export AWS_PROFILE=odot-internal   # For internal stacks
export AWS_PROFILE=odot-external   # For external stacks
```

When your session expires, re-authenticate with `aws sso login --profile <name>`. No reconfiguration needed.

### Terraform State Storage (Split-Account)

Each account hosts its own Terraform state — there is no separate management account:

| Account | State Bucket | DynamoDB Lock Table | Stores State For |
|---------|-------------|--------------------|--------------------|
| DOT-Web-Internal (577881328002) | `odot-terraform-state-577881328002` | `odot-terraform-locks` | Root backend, `internal-dev`, `internal-test`, `internal-prod` |
| DOT-Web-External (549136075921) | `odot-terraform-state-549136075921` | `odot-terraform-locks` | `external-dev`, `external-test`, `external-prod` |

This provides full isolation — each account owns its own state and lock table.

### Organization-Managed Security Services

The following services are already enabled at the AWS Organization level and should **not** be re-created by Terraform:

- **GuardDuty** — threat detection (org-delegated)
- **Security Hub** — compliance standards (org-delegated)
- **AWS Config** — configuration recording (org-delegated)
- **Macie** — sensitive data discovery (org-delegated)

When deploying platform stacks, set these flags in `terraform.tfvars` to skip creation:

```hcl
enable_guardduty   = false
enable_securityhub = false
enable_config      = false
enable_macie       = false
```

If your account does NOT have these services pre-enabled by the organization, leave them as `true` (the default) and Terraform will create them.

---

## 3. Terraform Backend Bootstrap

The Terraform remote backend must be created in **both** AWS accounts before any `terraform init` will succeed. Each account hosts its own state.

### Run the Bootstrap Script (Both Accounts)

```bash
# Bootstrap the Internal account
export AWS_PROFILE=odot-internal
cd odot-aws-platform/scripts
./bootstrap-backend.sh 577881328002

# Bootstrap the External account
export AWS_PROFILE=odot-external
./bootstrap-backend.sh 549136075921
```

Each run creates:
- **S3 bucket**: `odot-terraform-state-<ACCOUNT_ID>` (versioned, encrypted, public access blocked)
- **DynamoDB table**: `odot-terraform-locks` (partition key: `LockID`)

### Update Backend Configuration

The backend.tf files are pre-configured with the correct account IDs:

| File | State Bucket |
|------|-------------|
| `backend.tf` (root) | `odot-terraform-state-577881328002` |
| `stacks/internal-dev/backend.tf` | `odot-terraform-state-577881328002` |
| `stacks/internal-test/backend.tf` | `odot-terraform-state-577881328002` |
| `stacks/internal-prod/backend.tf` | `odot-terraform-state-577881328002` |
| `stacks/external-dev/backend.tf` | `odot-terraform-state-549136075921` |
| `stacks/external-test/backend.tf` | `odot-terraform-state-549136075921` |
| `stacks/external-prod/backend.tf` | `odot-terraform-state-549136075921` |

**If you need to reconfigure** (e.g., from a fresh clone), use the configure script with split-account mode:

```bash
./scripts/configure-backend.sh --internal 577881328002 --external 549136075921
```

This replaces `MGMT_ACCOUNT_ID` placeholders in all backend.tf files, routing internal stacks to the internal account bucket and external stacks to the external account bucket.

The script also supports single-account mode for backward compatibility:
```bash
./scripts/configure-backend.sh <ACCOUNT_ID>   # Uses same ID for all files
```

### Verify Backend Access

```bash
# Verify internal backend
export AWS_PROFILE=odot-internal
cd odot-aws-platform
terraform init

# Verify external backend
export AWS_PROFILE=odot-external
cd stacks/external-dev
terraform init
```

If these succeed without errors, the backends are correctly configured.

---

## 4. GitHub Repository Setup

### Organization Requirements

- [ ] Access to the **ODOT GitHub Enterprise** organization
- [ ] Organization-level permissions to create repositories and configure settings
- [ ] GitHub Actions enabled for the organization

### Create Repositories

Two repositories are needed:

| Repository | Purpose | Visibility |
|------------|---------|------------|
| `odot-aws-platform` | Shared Terraform modules and platform infrastructure | Internal |
| `odot-app-template` | Template repository for bootstrapping new applications | Template (Internal) |

### Upload the Platform Repository

```bash
cd odot-aws-platform
git init
git add .
git commit -m "feat: initial platform infrastructure"
git remote add origin https://github.com/ODOT-GitHub-Org/odot-aws-platform.git
git push -u origin main
```

### Upload the App Template Repository

```bash
cd odot-app-template
git init
git add .
git commit -m "feat: initial app template"
git remote add origin https://github.com/ODOT-GitHub-Org/odot-app-template.git
git push -u origin main
```

### Configure the App Template as a Template Repository

1. Go to **Settings** → **General** in the `odot-app-template` repository
2. Check **"Template repository"**
3. This enables the "Use this template" button for creating new app repos

### Branch Protection Rules

Configure these on **both** repositories:

**For `main` branch:**
- [ ] Require pull request reviews before merging (minimum 1 reviewer)
- [ ] Require status checks to pass before merging
- [ ] Require branches to be up to date before merging
- [ ] Do not allow bypassing the above settings

**For application repositories (`dev`, `test`, `prod` branches):**
- [ ] Require pull request reviews before merging
- [ ] Require status checks to pass (lint, unit tests, terraform validate)
- [ ] Restrict who can push to `prod` branch (authorized deployers only)

---

## 5. GitHub OIDC Federation (AWS ↔ GitHub)

GitHub Actions authenticates to AWS using OIDC — no long-lived credentials are stored in GitHub.

### Deploy the OIDC Module

The OIDC module must be deployed in **each AWS account** that GitHub Actions needs to access.

```bash
cd odot-aws-platform/stacks/internal-dev
```

The OIDC module requires these inputs:

| Variable | Value |
|----------|-------|
| `github_org` | Your GitHub Enterprise organization name (e.g., `ODOT-GitHub-Org`) |
| `github_repos` | List of repository names allowed to deploy (e.g., `["my-app", "fleet-tracker"]`) |
| `account_id` | The AWS account ID where the role is created |
| `account_type` | `"internal"` or `"external"` |

### What Gets Created

- **IAM OIDC Identity Provider** — trusts `token.actions.githubusercontent.com`
- **IAM Role** — `odot-github-actions-{account_type}` with least-privilege permissions for:
  - ECR: authenticate, push images
  - ECS: register task definitions, update services
  - IAM PassRole: scoped to `odot-ecs-task-*` roles only
- **Trust policy** — restricts role assumption to specific GitHub org/repos via `sub` claim

### Verify OIDC Setup

After deploying, note the IAM role ARN:
```
arn:aws:iam::<ACCOUNT_ID>:role/odot-github-actions-internal
arn:aws:iam::<ACCOUNT_ID>:role/odot-github-actions-external
```

These ARNs are needed for the GitHub repository variables in the next step.

---

## 6. GitHub Repository Variables and Secrets

The CI/CD pipeline references these **repository-level variables** (not secrets — OIDC eliminates the need for stored credentials).

### Required Repository Variables

Configure these in each application repository under **Settings → Secrets and variables → Actions → Variables**:

| Variable Name | Description | Example Value |
|---------------|-------------|---------------|
| `AWS_DEPLOY_ROLE_ARN` | IAM role ARN for OIDC authentication | `arn:aws:iam::577881328002:role/odot-github-actions-internal` |
| `ECR_REPOSITORY_NAME` | ECR repository name for this app | `odot-my-app-internal` |
| `ECS_CLUSTER_NAME` | ECS cluster name | `WebHosting-Dev` |
| `ECS_SERVICE_NAME` | ECS service name for this app | `my-app-dev` |

### How to Set Variables

**Via GitHub UI:**
1. Navigate to your repository → **Settings** → **Secrets and variables** → **Actions**
2. Click the **Variables** tab
3. Click **New repository variable**
4. Add each variable from the table above

**Via GitHub CLI:**
```bash
gh variable set AWS_DEPLOY_ROLE_ARN --body "arn:aws:iam::577881328002:role/odot-github-actions-internal"
gh variable set ECR_REPOSITORY_NAME --body "odot-my-app-internal"
gh variable set ECS_CLUSTER_NAME --body "WebHosting-Dev"
gh variable set ECS_SERVICE_NAME --body "my-app-dev"
```

### No Secrets Required

Because the pipeline uses OIDC federation, there are **no AWS access keys or secret keys** to store. The `AWS_DEPLOY_ROLE_ARN` variable is not sensitive — it's a public ARN.

---

## 7. GitHub Environments and Protection Rules

Production deployments require manual approval via GitHub Environments.

### Create the `production` Environment

1. Go to your application repository → **Settings** → **Environments**
2. Click **New environment**
3. Name it exactly: `production`
4. Configure protection rules:
   - [ ] **Required reviewers** — add authorized approvers (team leads, release managers)
   - [ ] **Wait timer** (optional) — add a delay before deployment starts
   - [ ] **Deployment branches** — restrict to `prod` branch only

### Why This Matters

The `deploy-prod` job in `ci-cd.yml` references `environment: production`. GitHub will pause the workflow and require approval from the configured reviewers before the production deployment proceeds.

---

## 7.5. Slack / AWS Chatbot Authorization

AWS Chatbot forwards CloudWatch alarm notifications to Slack. This requires a **manual one-time authorization** between your Slack workspace and each AWS account before Terraform can create the channel configuration.

### Why This Is Manual

AWS Chatbot uses an OAuth flow to connect Slack and AWS. There is no API or CLI command to perform this authorization — it must be done through the AWS Console and Slack's OAuth consent screen.

### Steps (Per AWS Account)

1. Log into the AWS Console for the target account (Internal or External)
2. Navigate to **[AWS Chatbot](https://console.aws.amazon.com/chatbot/)** (region: `us-east-2`)
3. Click **"Configure new client"** → select **Slack**
4. Sign in to your Slack workspace when redirected
5. Click **Allow** to authorize AWS Chatbot
6. You'll be redirected back to AWS — your workspace will appear in the list

### Get Your IDs

**Workspace ID:**
- Visible in the AWS Chatbot console after authorization (format: `T0XXXXXXXXX`)
- Also available in Slack: click your workspace name → **Settings & administration** → **Workspace settings** → the URL contains the workspace ID

**Channel ID:**
- In Slack, right-click the target channel → **View channel details** → scroll to bottom → **Channel ID** (format: `C0XXXXXXXXX`)

### Update Terraform Variables

Add the real IDs to your stack's `terraform.tfvars`:

```hcl
slack_workspace_id = "T0XXXXXXXXX"   # From AWS Chatbot console
slack_channel_id   = "C0XXXXXXXXX"   # From Slack channel details
```

### Current Configuration (Testing)

For initial testing, a demo Slack workspace is configured:

| Variable | Value | Notes |
|----------|-------|-------|
| `slack_workspace_id` | `T0B72DR9L5U` | Demo workspace — replace with enterprise when ready |
| `slack_channel_id` | `C0B74FW9W7L` | Demo channel — replace with `#aws-alerts-internal` when ready |

### Migrating to Enterprise Slack

When the enterprise Slack workspace is ready:

1. Authorize the enterprise workspace in AWS Chatbot (same steps as above)
2. Create dedicated channels: `#aws-alerts-internal` and `#aws-alerts-external`
3. Update `terraform.tfvars` in each stack with the new workspace and channel IDs
4. Run `terraform apply` — Chatbot will recreate the channel configuration pointing to the new workspace

### Conditional Behavior

If `slack_workspace_id` is empty or set to a placeholder (`T0000...`), the Chatbot resources are **skipped** during `terraform apply`. The SNS topic and email subscriptions are still created — you just won't get Slack notifications until a real workspace is authorized and configured.

---

## 8. Platform Infrastructure Deployment

Deploy the shared platform infrastructure **before** onboarding any applications.

### Automated Deployment

**Use `deploy-platform.sh` to deploy all stacks in the correct order:**

```bash
cd odot-aws-platform

# Plan all stacks (review without applying)
./scripts/deploy-platform.sh --plan-only

# Deploy internal stacks (requires odot-internal profile)
export AWS_PROFILE=odot-internal
./scripts/deploy-platform.sh internal

# Deploy external stacks (requires odot-external profile)
export AWS_PROFILE=odot-external
./scripts/deploy-platform.sh external

# Deploy a single stack
export AWS_PROFILE=odot-internal
./scripts/deploy-platform.sh internal-dev
```

### Deployment Order

The script deploys stacks in this dependency order:

```
1. internal-dev → internal-test → internal-prod
2. external-dev → external-test → external-prod
```

Each stack provisions: Networking → Security → OIDC → ECS Cluster → Monitoring.

### Manual Deployment (Alternative)

If you prefer to deploy stacks individually:

```bash
# Set the correct profile for the target account
export AWS_PROFILE=odot-internal   # For internal-* stacks
# export AWS_PROFILE=odot-external # For external-* stacks

cd odot-aws-platform/stacks/internal-dev
terraform init
terraform plan    # Review carefully
terraform apply
```

### Collect Output Values

**Automated:** After deploying, collect all stack outputs into a single file:

```bash
./scripts/collect-stack-outputs.sh
```

This creates `platform-outputs.json` with all values application teams need:

```bash
# Query a specific value
jq '."internal-dev".vpc_id.value' platform-outputs.json
jq '."internal-dev".cluster_arn.value' platform-outputs.json
```

| Output | Used For |
|--------|----------|
| `vpc_id` | App Terraform config |
| `private_subnet_ids` | ECS task placement |
| `public_subnet_ids` (external only) | ALB placement |
| `cluster_arn` | App Terraform config |
| `cluster_name` | App Terraform config + GitHub variable |
| `kms_key_arn` | App Terraform config |
| `sns_topic_arn` | App Terraform config |
| `waf_acl_arn` (external only) | App Terraform config |
| `github_actions_role_arn` | GitHub repository variable |

---

## 9. Application Onboarding

Once the platform is deployed, onboard a new application using the template.

### Automated Onboarding (Recommended)

**Use `onboard-app.sh` to automate the entire process:**

```bash
cd odot-aws-platform

./scripts/onboard-app.sh \
  --app-name "fleet-tracker" \
  --account-type "internal" \
  --github-org "ODOT-GitHub-Org"
```

This single command:
1. Creates a new repository from `odot-app-template`
2. Generates `terraform/terraform.tfvars` with values from `platform-outputs.json`
3. Sets all GitHub repository variables (`AWS_DEPLOY_ROLE_ARN`, `ECR_REPOSITORY_NAME`, etc.)
4. Creates and pushes `dev`, `test`, `prod` branches

**Additional options:**

```bash
./scripts/onboard-app.sh \
  --app-name "fleet-tracker" \
  --account-type "internal" \
  --github-org "ODOT-GitHub-Org" \
  --container-port 3000 \
  --cpu 512 \
  --memory 1024 \
  --runtime "linux" \
  --dry-run              # Preview without making changes
```

**After the script completes, you still need to:**
1. Review `terraform/terraform.tfvars` — replace any PLACEHOLDER values if platform outputs were unavailable
2. Run `terraform init && terraform apply` in the `terraform/` directory
3. Configure the `production` GitHub Environment with required reviewers (manual — GitHub API limitation)

### Manual Onboarding (Alternative)

If you prefer to onboard manually or need more control:

#### Step 1: Create Repository from Template

1. Go to `odot-app-template` on GitHub
2. Click **"Use this template"** → **"Create a new repository"**
3. Name it (e.g., `odot-fleet-tracker`)
4. Set visibility to **Internal**

#### Step 2: Configure Terraform Variables

```bash
git clone https://github.com/ODOT-GitHub-Org/odot-fleet-tracker.git
cd odot-fleet-tracker
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars` with your app-specific values and the platform outputs from Step 8.

#### Step 3: Configure S3 Backend

Uncomment and fill in the `backend "s3"` block in `terraform/main.tf`:

```hcl
backend "s3" {
  bucket         = "odot-terraform-state-<ACCOUNT_ID>"
  key            = "apps/fleet-tracker/terraform.tfstate"
  region         = "us-east-2"
  dynamodb_table = "odot-terraform-locks"
  encrypt        = true
}
```

Use the account ID matching your target account:
- Internal apps → `577881328002`
- External apps → `549136075921`

#### Step 4: Provision App Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This creates: ECR repository, ECS service, ALB, target group, auto-scaling, CloudWatch alarms, and IAM roles.

#### Step 5: Set GitHub Variables

Using the outputs from `terraform apply`:

```bash
gh variable set AWS_DEPLOY_ROLE_ARN --body "<role ARN from OIDC module>"
gh variable set ECR_REPOSITORY_NAME --body "<ECR repo name from terraform output>"
gh variable set ECS_CLUSTER_NAME --body "<cluster name>"
gh variable set ECS_SERVICE_NAME --body "<ECS service name from terraform output>"
```

#### Step 6: Create Protected Branches

```bash
git checkout -b dev
git push -u origin dev

git checkout -b test
git push -u origin test

git checkout -b prod
git push -u origin prod
```

#### Step 7: First Deployment

```bash
git checkout dev
# Add your application code
git add .
git commit -m "feat: initial application"
git push origin dev
```

The CI/CD pipeline triggers automatically and deploys to the Dev environment.

---

## 10. Verification Checklist

### Automated Verification (Recommended)

**Run the verification script to check all prerequisites at once:**

```bash
cd odot-aws-platform

./scripts/verify-prerequisites.sh \
  --app-name "fleet-tracker" \
  --account-type "internal" \
  --stage "dev" \
  --github-org "ODOT-GitHub-Org"
```

The script checks:
- Local tools (terraform, aws, docker, gh, git, jq)
- AWS resources (ECS cluster, ECR repo, OIDC role, KMS key, SNS topic, state bucket)
- GitHub configuration (repo exists, variables set, branches created, environment configured)

**Options for partial checks:**
```bash
# Skip AWS checks (no credentials available)
./scripts/verify-prerequisites.sh ... --skip-aws

# Skip GitHub checks (no gh CLI)
./scripts/verify-prerequisites.sh ... --skip-github
```

### Manual Checklist

Use this if you prefer to verify manually or need to check items the script can't reach.

### AWS Prerequisites

- [ ] Internal account has S3 state bucket (`odot-terraform-state-577881328002`) and DynamoDB lock table
- [ ] External account has S3 state bucket (`odot-terraform-state-549136075921`) and DynamoDB lock table
- [ ] Internal account (577881328002) is accessible via IAM Identity Center (`aws sts get-caller-identity --profile odot-internal`)
- [ ] External account (549136075921) is accessible via IAM Identity Center (`aws sts get-caller-identity --profile odot-external`)
- [ ] Service-linked roles exist for ECS and ELB in both accounts
- [ ] OIDC identity provider is deployed in target account(s)
- [ ] IAM role `odot-github-actions-{type}` exists with correct trust policy
- [ ] VPC and subnets are deployed in target account-stage
- [ ] ECS cluster is deployed and active
- [ ] KMS key exists and is accessible
- [ ] SNS topic exists for alarm notifications

### GitHub Prerequisites

- [ ] Organization has GitHub Actions enabled
- [ ] Platform repository (`odot-aws-platform`) is pushed and accessible
- [ ] App template repository is marked as a template
- [ ] Application repository is created from template
- [ ] Branch protection rules are configured on `dev`, `test`, `prod`
- [ ] Repository variables are set (`AWS_DEPLOY_ROLE_ARN`, `ECR_REPOSITORY_NAME`, `ECS_CLUSTER_NAME`, `ECS_SERVICE_NAME`)
- [ ] `production` environment is created with required reviewers
- [ ] GitHub Actions workflows are visible in the Actions tab

### Application Prerequisites

- [ ] `terraform/terraform.tfvars` is configured with correct values
- [ ] `terraform/main.tf` backend block is uncommented and filled in
- [ ] `terraform apply` completed successfully (ECR, ECS service, ALB created)
- [ ] Dockerfile builds locally: `docker build -t app:local .`
- [ ] Health check responds: `curl http://localhost:8080/health` returns 200
- [ ] `dev`, `test`, `prod` branches exist in the repository

### First Deployment Verification

- [ ] Push to `dev` triggers the CI/CD pipeline
- [ ] Unit tests pass
- [ ] Security scans pass (no Critical/High findings)
- [ ] Docker image is pushed to ECR (check with `aws ecr list-images`)
- [ ] ECS service updates and tasks reach RUNNING state
- [ ] ALB health checks pass (target shows "healthy")
- [ ] Application is accessible via ALB DNS name

---

## Troubleshooting Quick Reference

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| `terraform init` fails | Backend bucket doesn't exist | Run `bootstrap-backend.sh` |
| OIDC role assumption fails | Repo not in `github_repos` list | Add repo to OIDC module and redeploy |
| ECR push "access denied" | Wrong `AWS_DEPLOY_ROLE_ARN` variable | Verify the role ARN matches the target account |
| ECS service won't stabilize | Container crashes on start | Check CloudWatch logs at `/ecs/{app}/{stage}` |
| Pipeline skips deploy stage | Push was to wrong branch | Verify branch name matches `dev`/`test`/`prod` exactly |
| Production deploy hangs | No approver configured | Add reviewers to the `production` environment |

---

---

## 11. TLS/DNS Prerequisites

Every application requires HTTPS. Before deploying an app, ensure:

### Route 53 Hosted Zone

- [ ] A Route 53 hosted zone exists for your domain (e.g., `odot.ohio.gov`)
- [ ] The hosted zone is delegated from the parent domain (NS records configured)
- [ ] Note the **Hosted Zone ID** — needed for `terraform.tfvars`

### Application Variables for TLS

Add these to your `terraform.tfvars`:

```hcl
domain_name    = "fleet-tracker.dev.odot.ohio.gov"
hosted_zone_id = "Z0123456789ABCDEFGHIJ"
certificate_arn = ""  # Leave empty to auto-create via DNS validation
```

ACM certificates are created automatically by the `app-service` module. DNS validation records are added to Route 53 automatically. Validation typically completes within 5–30 minutes.

---

## 12. Admin Dashboard Setup

The Admin Dashboard requires Okta federation and cross-account IAM roles.

### Okta Configuration

- [ ] Create an OIDC App Integration in Okta (Authorization Code flow)
- [ ] Create groups: `ODOT-Web-Developers` and `ODOT-Web-Admins`
- [ ] Assign users to groups
- [ ] Store the Okta client secret in Secrets Manager:
  ```bash
  aws secretsmanager create-secret \
    --name "odot/dashboard/okta-client-secret" \
    --secret-string "<okta-client-secret>" \
    --kms-key-id alias/odot-internal \
    --region us-east-2
  ```

### Dashboard Terraform Variables

```hcl
okta_issuer_url        = "https://odot.okta.com/oauth2/default"
okta_client_id         = "<from Okta>"
okta_client_secret_arn = "arn:aws:secretsmanager:us-east-2:577881328002:secret:odot/dashboard/okta-client-secret-XXXXXX"
cognito_domain_prefix  = "odot-dashboard-prod"
callback_urls          = ["https://dashboard.internal.odot.ohio.gov/callback"]
logout_urls            = ["https://dashboard.internal.odot.ohio.gov/logout"]
internal_account_id    = "577881328002"
external_account_id    = "549136075921"
```

See `admin-dashboard/docs/okta-setup.md` and `admin-dashboard/docs/cognito-setup.md` for detailed step-by-step guides.

---

## 13. Automatic Infrastructure (No Manual Setup Required)

The following are provisioned automatically by the platform modules:

| Feature | Module | What It Does |
|---------|--------|--------------|
| VPC Endpoints (Internal) | `networking` | 7 interface + 1 S3 gateway endpoint for zero-egress |
| WAF Managed Rules (External) | `app-service` | Common, Bad Inputs, SQLi rule groups + rate limiting |
| NIST 800-53 Compliance | `security` | Security Hub standard enabled alongside FSBP |
| Tag Governance | `management` | Org-level tag policy enforcing Environment/Project/Owner |
| Resilience Testing | `resilience` | FIS experiment templates for AZ failure + circuit breaker |
| Audit Archive | `admin-dashboard` | S3 Object Lock (365-day COMPLIANCE) for tamper-evident audit |

---

## 14. Platform CI Pipeline

The `odot-aws-platform` repository runs these checks on every PR:

- **tfsec** — static security analysis (fails on HIGH/CRITICAL)
- **OPA/Conftest** — policy-as-code (tags, SG rules, encryption)
- **Go property tests** — 80+ tests validating module correctness

PRs that fail cannot be merged. See `.github/workflows/platform-ci.yml`.

---

## Keeping This Document Updated

As the platform evolves, update this document when:
- New AWS services or accounts are added
- GitHub Actions workflows change their variable requirements
- New prerequisites are introduced (tools, permissions, configuration)
- Deployment procedures change

Last verified: May 29, 2026

---

## Deployment Progress Tracker

Track what has been completed and what remains. Update this section as you progress.

### Completed (Internal Account — 577881328002)

- [x] IAM Identity Center (SSO) configured — profile `odot-internal`
- [x] Terraform backend bootstrapped — bucket `odot-terraform-state-577881328002`
- [x] Backend.tf files configured (split-account mode)
- [x] GitHub repos created — `ftvizsla/odot-aws-platform`, `ftvizsla/odot-app-template`
- [x] Platform stack `internal-dev` deployed (VPC, ECS cluster, KMS, OIDC, monitoring)
- [x] GitHub OIDC federation — role `odot-github-actions-internal` trusts `ftvizsla/*`
- [x] GitHub repository variables set on both repos
- [x] GitHub `production` environment created on `odot-app-template`
- [x] Slack/Chatbot authorized — workspace `T0B72DR9L5U`, channel `C0B74FW9W7L`
- [x] Application `odot-app-template` onboarded — ECR, ECS service, ALB, alarms deployed

### Remaining (Internal Account)

- [ ] Push a Docker image to ECR and verify ECS tasks start healthy
- [ ] Deploy `internal-test` stack
- [ ] Deploy `internal-prod` stack
- [ ] Set up TLS/DNS (ACM certificate + Route 53) for HTTPS on ALB
- [ ] Configure CI/CD pipeline end-to-end (push to `dev` → auto-deploy)

### Remaining (External Account — 549136075921)

- [ ] Configure SSO profile `odot-external`
- [ ] Bootstrap Terraform backend — `./scripts/bootstrap-backend.sh 549136075921`
- [ ] Authorize Slack/Chatbot in external account
- [ ] Deploy `external-dev` stack
- [ ] Deploy `external-test` stack
- [ ] Deploy `external-prod` stack
- [ ] Onboard first external application

### Remaining (Enterprise Migration)

- [ ] Obtain access to ODOT GitHub Enterprise organization
- [ ] Migrate repos from `ftvizsla` to enterprise org
- [ ] Update OIDC module `github_org` variable and redeploy
- [ ] Update GitHub repository variables with new role ARNs (if org name changes)
- [ ] Configure branch protection rules (requires GitHub Team/Enterprise plan)
- [ ] Add required reviewers to `production` environment

### Remaining (Okta / Admin Dashboard)

- [ ] Set up Okta OIDC App Integration
- [ ] Create Okta groups (`ODOT-Web-Developers`, `ODOT-Web-Admins`)
- [ ] Store Okta client secret in Secrets Manager
- [ ] Deploy admin dashboard infrastructure
- [ ] Replace demo Slack workspace with enterprise Slack

### Known Issues / Workarounds Applied

| Issue | Workaround | Permanent Fix |
|-------|-----------|---------------|
| GuardDuty/SecurityHub/Config already org-managed | `enable_*` flags set to `false` in tfvars | No fix needed — this is correct for org-delegated accounts |
| No ACM certificate yet | HTTPS listener skipped; ALB serves HTTP on port 80 | Create ACM cert + Route 53 hosted zone, add `certificate_arn` to tfvars |
| CloudWatch log group KMS encryption | Removed KMS from log group (key policy needs `logs.amazonaws.com` grant) | Update KMS key policy in security module to allow CloudWatch Logs |
| GitHub Free plan | No environment protection rules (approval gates) | Migrate to GitHub Team/Enterprise |
| ECS tasks crash-looping | No Docker image in ECR yet | Push initial image via CI/CD or manually |

