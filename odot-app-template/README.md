# ODOT App Template

The **ODOT Web Application Template** is a GitHub repository template for bootstrapping new web applications on the ODOT AWS hosting platform. It provides pre-configured CI/CD pipelines, Terraform infrastructure definitions, and a production-ready Dockerfile — enabling developers to go from zero to deployed in under 15 minutes.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Architecture Overview](#architecture-overview)
- [Repository Structure](#repository-structure)
- [Configuration Reference](#configuration-reference)
- [Deployment Workflow](#deployment-workflow)
- [Dockerfile Guide](#dockerfile-guide)
- [Terraform Infrastructure](#terraform-infrastructure)
- [Security](#security)
- [Monitoring and Alerts](#monitoring-and-alerts)
- [Troubleshooting](#troubleshooting)
- [Requirements](#requirements)

---

## Quick Start

### 1. Create Your Repository

Create a new repository from this template in the ODOT GitHub Enterprise organization:

1. Click **"Use this template"** → **"Create a new repository"**.
2. Name your repository (e.g., `odot-fleet-tracker`).
3. Set visibility to **Internal** (for corporate apps) or **Private** (for public-facing apps).

### 2. Configure Your Application

```bash
# Clone your new repository
git clone https://github.com/ODOT-GitHub-Org/your-app-name.git
cd your-app-name

# Copy the example Terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars` — set at minimum:

```hcl
app_name       = "your-app-name"    # Unique, lowercase, hyphens only
runtime        = "linux"             # or "windows"
container_port = 8080                # Port your app listens on
```

Get infrastructure values (`vpc_id`, `cluster_arn`, etc.) from the platform team.

### 3. Provision Infrastructure

```bash
cd terraform
terraform init
terraform plan     # Review what will be created
terraform apply    # Creates ECR, ECS service, ALB, alarms, IAM roles
```

### 4. Deploy Your Application

```bash
# Add your application code, then push to dev
git add .
git commit -m "feat: initial application"
git push origin dev
```

The CI/CD pipeline automatically builds, scans, and deploys your application to the Dev environment.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        GitHub Enterprise                              │
│                                                                       │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────────────┐  │
│  │ Push to dev │───►│ CI/CD Pipeline│───►│ ECR (Docker Registry)  │  │
│  │ /test/prod  │    │              │    │ Tagged: SHA + branch    │  │
│  └─────────────┘    │ 1. Unit Test │    └───────────┬────────────┘  │
│                      │ 2. Scan      │                │               │
│                      │ 3. Build     │                │               │
│                      │ 4. Deploy    │                ▼               │
│                      └──────────────┘    ┌────────────────────────┐  │
│                                          │ ECS Fargate Service    │  │
│                                          │ (Rolling Deployment)   │  │
│                                          └────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘

AWS Account (Internal or External)
┌─────────────────────────────────────────────────────────────────────┐
│  VPC                                                                 │
│  ┌──────────────────┐     ┌──────────────────────────────────────┐  │
│  │ ALB              │────►│ ECS Fargate Cluster                  │  │
│  │ (+ WAF if ext.)  │     │ ┌────────┐ ┌────────┐ ┌────────┐   │  │
│  │ (+ Shield Std.)  │     │ │ Task 1 │ │ Task 2 │ │ Task N │   │  │
│  └──────────────────┘     │ └────────┘ └────────┘ └────────┘   │  │
│                            │ Auto-scaling: min=2, max=50         │  │
│                            └──────────────────────────────────────┘  │
│                                                                       │
│  ┌──────────────────┐     ┌──────────────────────────────────────┐  │
│  │ CloudWatch       │     │ SNS → Chatbot → Slack                │  │
│  │ Logs + Alarms    │────►│ #aws-alerts-internal/external        │  │
│  └──────────────────┘     └──────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Purpose |
|-----------|---------|
| **ECR** | Private Docker image registry (scan-on-push, KMS encrypted) |
| **ECS Fargate** | Serverless container compute (no EC2 to manage) |
| **ALB** | Load balancer with health checks and traffic distribution |
| **WAF** | Web Application Firewall (external account only) |
| **CloudWatch** | Logs, metrics, dashboards, and alarms |
| **Auto-scaling** | Scales tasks 2–50 based on CPU/memory utilization |

### Environments

| Stage | Account | Access | Capacity |
|-------|---------|--------|----------|
| Dev | Internal or External | Developers | Fargate Spot (cost-optimized) |
| Test | Internal or External | QA team | Fargate Spot (cost-optimized) |
| Prod | Internal or External | All users | Fargate On-Demand (reliable) |

---

## Repository Structure

```
odot-app-template/
├── .github/
│   └── workflows/
│       ├── ci-cd.yml              # Build, scan, and deploy pipeline
│       └── pr-checks.yml          # PR validation (lint, tests, terraform validate)
├── terraform/
│   ├── main.tf                    # Calls app-service module from odot-aws-platform
│   ├── variables.tf               # All input variable declarations
│   └── terraform.tfvars.example   # Example values with inline documentation
├── Dockerfile                     # Multi-stage build, non-root user, Alpine base
├── CONTRIBUTING.md                # Developer guide (routes, Dockerfile, deployments)
└── README.md                      # This file
```

### What Each File Does

| File | Purpose |
|------|---------|
| `ci-cd.yml` | Triggers on push to `dev`/`test`/`prod`; runs tests, scans, builds, and deploys |
| `pr-checks.yml` | Triggers on PRs; runs lint, unit tests, and `terraform validate` |
| `terraform/main.tf` | Provisions all AWS resources by calling the shared `app-service` module |
| `terraform/variables.tf` | Declares all configurable inputs with validation rules |
| `terraform/terraform.tfvars.example` | Documented example — copy to `terraform.tfvars` |
| `Dockerfile` | Multi-stage build template; customize for your runtime |

---

## Configuration Reference

### Application Variables (You Set These)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `app_name` | string | — | Unique identifier (3-30 chars, lowercase, hyphens). Used in all resource names. |
| `runtime` | string | `"linux"` | Container platform: `"linux"` or `"windows"` |
| `container_port` | number | `8080` | Port your application listens on |
| `cpu` | number | `256` | Fargate CPU units: 256, 512, 1024, 2048, or 4096 |
| `memory` | number | `512` | Fargate memory in MiB (must be valid for chosen CPU) |
| `owner` | string | `"odot-platform-team"` | Owner tag for cost allocation |

### Infrastructure Variables (Platform Team Provides)

| Variable | Type | Description |
|----------|------|-------------|
| `aws_region` | string | AWS region (default: `us-east-2`) |
| `account_type` | string | `"internal"` (corporate) or `"external"` (public-facing) |
| `stage` | string | `"dev"`, `"test"`, or `"prod"` |
| `vpc_id` | string | VPC ID for the target account-stage |
| `private_subnet_ids` | list(string) | Private subnets for ECS tasks (min 2 AZs) |
| `alb_subnet_ids` | list(string) | Subnets for the ALB |
| `cluster_arn` | string | ECS cluster ARN |
| `cluster_name` | string | ECS cluster name (e.g., `WebHosting-Dev`) |
| `kms_key_arn` | string | KMS key for ECR and log encryption |
| `waf_acl_arn` | string | WAF ACL ARN (required for external; `""` for internal) |
| `sns_topic_arn` | string | SNS topic for alarm notifications |
| `domain_name` | string | FQDN for the app (e.g., `myapp.dev.odot.ohio.gov`) |
| `hosted_zone_id` | string | Route 53 hosted zone ID for DNS |
| `certificate_arn` | string | ACM cert ARN (leave empty to auto-create) |

### CPU/Memory Combinations

| CPU (units) | Valid Memory (MiB) |
|-------------|-------------------|
| 256 | 512, 1024, 2048 |
| 512 | 1024 – 4096 |
| 1024 | 2048 – 8192 |
| 2048 | 4096 – 16384 |
| 4096 | 8192 – 30720 |

> Windows containers require minimum `cpu = 1024`.

---

## Deployment Workflow

### Branch-to-Environment Mapping

```
feature/* ──► dev ──► test ──► prod
               │        │        │
               ▼        ▼        ▼
           Dev Env  Test Env  Prod Env
          (auto)    (auto)   (approval)
```

### Pipeline Stages

Every push to `dev`, `test`, or `prod` triggers the CI/CD pipeline:

```
┌────────────┐    ┌──────────────┐    ┌────────────┐    ┌──────────┐
│ Unit Tests │───►│ Security Scan│───►│ Build+Push │───►│  Deploy  │
│            │    │ Trivy        │    │ Docker     │    │  ECS     │
│ Halt on    │    │ Inspector    │    │ ECR push   │    │  Rolling │
│ failure    │    │ CodeQL       │    │ SHA tag    │    │  Update  │
└────────────┘    └──────────────┘    └────────────┘    └──────────┘
```

| Stage | What Happens | Failure Behavior |
|-------|--------------|------------------|
| **Unit Tests** | Runs your test suite | Pipeline halts; no image built |
| **Security Scan** | Trivy + Inspector + CodeQL | Pipeline halts if Critical/High found |
| **Build & Push** | Docker build → ECR push | Pipeline halts on build error |
| **Deploy** | ECS rolling deployment | ECS auto-rollback via circuit breaker |

### Image Tagging

Each successful build produces two ECR image tags:
- `{40-char-git-sha}` — immutable, for audit and rollback
- `{branch}-latest` — mutable, always points to the newest build for that branch

### Production Approval

Pushes to `prod` require manual approval before deployment. Authorized approvers are configured in the GitHub repository's Environment settings under **Settings → Environments → production**.

### Authentication

The pipeline authenticates to AWS using OIDC federation — no long-lived AWS credentials are stored in GitHub. The `AWS_DEPLOY_ROLE_ARN` repository variable points to the IAM role created by the OIDC module.

---

## Dockerfile Guide

The template includes a multi-stage Dockerfile optimized for security and size.

### Default Template (Node.js)

```dockerfile
FROM node:20-alpine AS build       # Build stage with full toolchain
FROM node:20-alpine AS production  # Minimal runtime
USER 1000                          # Non-root execution
EXPOSE 8080                        # Must match container_port
HEALTHCHECK ...                    # Required for ALB integration
```

### Customization Points

| What to Change | Where |
|----------------|-------|
| Base image / runtime | `FROM` lines in both stages |
| System dependencies | `RUN apk add ...` in build stage |
| Application port | `EXPOSE` directive + `container_port` in tfvars |
| Build commands | `RUN npm ci`, `RUN pip install`, etc. |
| Start command | `CMD` at the end |

### Requirements

- **Non-root user**: Linux containers must run as UID 1000 (enforced by ECS task definition).
- **Health check**: Must respond to `GET /health` with HTTP 200 on `container_port`.
- **Single port**: Expose only one port matching your `container_port` variable.
- **Read-only filesystem**: The root filesystem is read-only. Use `/tmp` for temporary files.

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed examples of different runtimes.

---

## Terraform Infrastructure

### What Gets Created

Running `terraform apply` in the `terraform/` directory provisions:

| Resource | Purpose |
|----------|---------|
| ECR Repository | Private Docker image registry with scan-on-push |
| ECS Task Definition | Container configuration (CPU, memory, ports, security) |
| ECS Service | Manages running tasks with rolling deployments |
| ALB + Target Group | Load balancer with health checks |
| WAF Association | Web Application Firewall (external account only) |
| Auto-scaling | Scales tasks between 2 and 50 based on utilization |
| CloudWatch Log Group | Application logs (90 days dev/test, 365 days prod) |
| CloudWatch Alarms | CPU, memory, 5xx rate, and task count alerts |
| IAM Roles | Least-privilege execution and task roles |

### Module Source

The `terraform/main.tf` file calls the `app-service` module from the shared platform repository:

```hcl
module "app_service" {
  source = "git::https://github.com/ODOT-GitHub-Org/odot-aws-platform.git//modules/app-service?ref=main"
  # ...
}
```

Pin the `ref` to a specific tag or commit for production stability:

```hcl
source = "git::https://github.com/ODOT-GitHub-Org/odot-aws-platform.git//modules/app-service?ref=v1.2.0"
```

### State Management

Terraform state is stored remotely in S3 with DynamoDB locking:

```hcl
backend "s3" {
  bucket         = "odot-terraform-state-{account-id}"
  key            = "apps/{app_name}/terraform.tfstate"
  region         = "us-east-2"
  dynamodb_table = "odot-terraform-locks"
  encrypt        = true
}
```

---

## Security

### Container Security

- **Read-only root filesystem** — prevents runtime file modification (Linux only)
- **Non-root execution** — containers run as UID 1000
- **Minimal base images** — Alpine-based to reduce attack surface
- **Multi-stage builds** — build tools excluded from production image

### Pipeline Security

- **OIDC authentication** — no long-lived AWS credentials stored in GitHub
- **Vulnerability scanning** — Trivy, Amazon Inspector, and CodeQL on every build
- **Critical/High gate** — deployments blocked if serious vulnerabilities found
- **ECR scan-on-push** — images scanned again when pushed to registry
- **KMS encryption** — all images and logs encrypted at rest

### Network Security

- **Internal account** — no internet access; zero-egress VPC with VPC endpoints for AWS services; reachable only via Client VPN or Direct Connect
- **External account** — WAF with managed rules (OWASP Top 10, SQLi, rate limiting) + Shield Standard on all ALBs
- **HTTPS everywhere** — TLS 1.3 on all ALBs; HTTP automatically redirects to HTTPS
- **Private subnets** — ECS tasks run in private subnets (NAT gateway for egress in external account; VPC endpoints in internal account)

### Distributed Tracing (Optional)

Enable distributed tracing by setting `enable_tracing = true` in your Terraform variables. This adds an AWS Distro for OpenTelemetry (ADOT) sidecar to your task definition that exports traces to AWS X-Ray. See [CONTRIBUTING.md](CONTRIBUTING.md) for SDK setup instructions per runtime.

---

## Monitoring and Alerts

### CloudWatch Alarms

Each application automatically gets four CloudWatch alarms:

| Alarm | Threshold | Period |
|-------|-----------|--------|
| CPU Utilization | > 80% | 5 minutes |
| Memory Utilization | > 80% | 5 minutes |
| ALB 5xx Error Rate | > 1% | 5 minutes |
| ECS Task Count | < 2 (minimum) | Immediate |

### Auto-Scaling

| Trigger | Action | Cooldown |
|---------|--------|----------|
| CPU or Memory > 70% for 3 min | Scale out (add tasks) | — |
| CPU and Memory < 30% for 10 min | Scale in (remove tasks) | — |
| Minimum tasks | 2 | Always maintained |
| Maximum tasks | 50 | Hard limit |

### Logs

Application logs are available in CloudWatch at:

```
/ecs/{app_name}/{stage}
```

View logs via AWS CLI:

```bash
aws logs tail /ecs/my-app/dev --follow --region us-east-2
```

### Notifications

Alarms route to Slack via AWS Chatbot:
- Internal apps: `#aws-alerts-internal`
- External apps: `#aws-alerts-external`

Alarms also route to email for ServiceNow/FortiSIEM integration.

---

## Troubleshooting

### Deployment Fails — Container Won't Start

1. Check CloudWatch logs:
   ```bash
   aws logs tail /ecs/{app_name}/{stage} --follow
   ```
2. Common causes:
   - Missing environment variables
   - Port mismatch (app listens on wrong port)
   - Writing to read-only filesystem (use `/tmp`)
   - Health check endpoint not responding

### Deployment Fails — Security Scan

- **Trivy Critical/High**: Update the vulnerable dependency or base image
- **Inspector finding**: Check the SBOM report in the Actions log for the specific CVE
- **CodeQL alert**: Review the code quality finding in GitHub Security tab

### Terraform Errors

| Error | Solution |
|-------|----------|
| `Error acquiring state lock` | Previous apply was interrupted. Ask platform team to release the DynamoDB lock. |
| `Module source not found` | Check GitHub access. Verify the `source` URL and `ref` in `main.tf`. |
| `Invalid value for variable` | Check variable validation rules in `variables.tf`. |
| `Error configuring S3 Backend` | Uncomment and fill in the `backend "s3"` block in `main.tf`. |

### Health Check Failures

The ALB expects `GET /health` to return HTTP 200 on your `container_port`. Verify:

```bash
# Test locally
docker build -t my-app:local .
docker run -p 8080:8080 my-app:local
curl http://localhost:8080/health
```

### Windows Container Issues

- Minimum CPU is 1024 (not 256 or 512)
- `readonlyRootFilesystem` is not supported — the platform handles this automatically
- Fargate Spot is not used for Windows tasks (falls back to on-demand)

---

## Requirements

- **Terraform** >= 1.5
- **Docker** (for local builds and testing)
- **AWS CLI** v2 (for log viewing and debugging)
- **Access** to ODOT AWS accounts via IAM Identity Center
- **GitHub** access to the ODOT GitHub Enterprise organization

---

## Related Resources

- **Platform Repository**: [`odot-aws-platform`](https://github.com/ODOT-GitHub-Org/odot-aws-platform) — Terraform modules and platform documentation
- **Contributing Guide**: [CONTRIBUTING.md](CONTRIBUTING.md) — how to add routes, update Dockerfile, and trigger deployments
- **Platform Runbook**: `odot-aws-platform/docs/runbook.md` — operational procedures
- **Architecture Diagrams**: `odot-aws-platform/docs/architecture/` — network, CI/CD, and ECS diagrams
