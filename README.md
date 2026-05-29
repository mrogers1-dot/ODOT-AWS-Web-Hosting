# ODOT AWS Web Hosting Platform

A fully automated, secure, and scalable web application hosting environment on AWS — built for the Ohio Department of Transportation. This monorepo contains the shared platform infrastructure (Terraform), a reusable application template, and an operational admin dashboard.

---

## What This Platform Does

- Hosts containerized web applications on **ECS Fargate** (no EC2 to manage)
- Supports **internal** (VPN/Direct Connect only) and **external** (public-facing with WAF) workloads
- Provides **six isolated environments**: Dev, Test, Prod × two AWS accounts
- Deploys via **GitHub Actions + OIDC** — no stored AWS credentials
- Enforces security with **tfsec, OPA/Conftest, NIST 800-53 alignment**, and scan-on-push
- Onboards new applications in **under 15 minutes** using a template repository and automation scripts

---

## Repository Structure

```
AWS-WebHosting/
├── odot-aws-platform/       # Shared Terraform modules, stacks, scripts, tests, and docs
├── odot-app-template/       # GitHub template repo for bootstrapping new applications
├── admin-dashboard/         # Operational management UI (React + Express)
├── DEPLOYMENT-PREREQUISITES.md  # End-to-end deployment checklist and automation guide
└── README.md                # ← You are here
```

---

## Quick Links — Documentation Index

### Platform Infrastructure

| Document | Description |
|----------|-------------|
| [odot-aws-platform/README.md](odot-aws-platform/README.md) | Platform architecture, module reference, stack deployment, testing, and contributing guide |
| [Architecture: Network Topology](odot-aws-platform/docs/architecture/network-topology.md) | VPC layout, subnets, endpoints, and connectivity |
| [Architecture: ECS Cluster Layout](odot-aws-platform/docs/architecture/ecs-cluster-layout.md) | Cluster design, capacity providers, and scaling |
| [Architecture: CI/CD Pipeline](odot-aws-platform/docs/architecture/cicd-pipeline.md) | GitHub Actions workflow, OIDC, and deployment stages |
| [Compliance: NIST 800-53 Mapping](odot-aws-platform/docs/compliance/nist-800-53-mapping.md) | Control family mapping to AWS services |
| [Runbook](odot-aws-platform/docs/runbook.md) | Operational procedures for incidents and maintenance |

### Application Template

| Document | Description |
|----------|-------------|
| [odot-app-template/README.md](odot-app-template/README.md) | Quick start, architecture overview, configuration reference, Dockerfile guide, and troubleshooting |
| [odot-app-template/CONTRIBUTING.md](odot-app-template/CONTRIBUTING.md) | Branch strategy, adding routes, updating Dockerfiles, triggering deployments, and PR process |

### Admin Dashboard

| Document | Description |
|----------|-------------|
| [admin-dashboard/README.md](admin-dashboard/README.md) | Dashboard features, local development, API endpoints, and deployment |
| [Admin Actions Reference](admin-dashboard/docs/admin-actions-reference.md) | Full reference for all admin operations |
| [Okta Setup](admin-dashboard/docs/okta-setup.md) | Okta OIDC integration configuration |
| [Cognito Setup](admin-dashboard/docs/cognito-setup.md) | AWS Cognito user pool and federation setup |
| [Role Management](admin-dashboard/docs/role-management.md) | RBAC roles, permissions, and group mapping |

### Deployment & Onboarding

| Document | Description |
|----------|-------------|
| [DEPLOYMENT-PREREQUISITES.md](DEPLOYMENT-PREREQUISITES.md) | Complete checklist: local tooling, AWS accounts, Terraform backend, GitHub setup, OIDC, platform deployment, app onboarding, and verification |

---

## Architecture at a Glance

```
AWS Organizations (Management Account)
└── OU: ODOT-Web
    ├── DOT-Web-Internal (577881328002)   ← private workloads (VPN/DC only)
    │   ├── internal-dev    (ECS Fargate Spot)
    │   ├── internal-test   (ECS Fargate Spot)
    │   └── internal-prod   (ECS Fargate On-Demand)
    └── DOT-Web-External (549136075921)   ← public workloads (WAF + Shield)
        ├── external-dev    (ECS Fargate Spot)
        ├── external-test   (ECS Fargate Spot)
        └── external-prod   (ECS Fargate On-Demand)
```

### Key Design Decisions

- **Zero-egress internal VPCs** — VPC endpoints for all AWS service access, no NAT/IGW
- **WAF managed rules on external ALBs** — OWASP Top 10, SQLi, rate limiting
- **HTTPS everywhere** — TLS 1.3 with automatic ACM certificate management
- **Module-per-concern** — reusable Terraform modules shared across all six stacks
- **Policy-as-code** — tfsec + OPA/Conftest gate on every platform PR
- **Least-privilege IAM** — scoped roles for GitHub Actions, ECS tasks, and dashboard

---

## Platform Modules

| Module | Purpose |
|--------|---------|
| `networking` | VPC, subnets, route tables, VPC endpoints (internal) / NAT + IGW (external) |
| `ecs-cluster` | ECS cluster, Fargate capacity providers, Container Insights |
| `app-service` | Per-app ECS service, task def, ALB (HTTPS), ECR, auto-scaling, CloudWatch alarms |
| `security` | GuardDuty, Security Hub (FSBP + NIST), Config, Macie, KMS, SCPs |
| `monitoring` | CloudWatch dashboards, SNS → Chatbot → Slack, Budgets, EventBridge |
| `oidc` | GitHub OIDC identity provider + IAM roles for CI/CD |
| `admin-dashboard` | Cognito (Okta federation), DynamoDB audit, cross-account roles, audit archive |
| `resilience` | AWS FIS experiment templates for AZ failure and circuit breaker testing |

---

## Getting Started

### Prerequisites

| Tool | Minimum Version |
|------|-----------------|
| [Terraform](https://www.terraform.io/downloads) | 1.5.0 |
| [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | 2.x |
| [Docker](https://docs.docker.com/get-docker/) | 20.x |
| [Go](https://go.dev/dl/) | 1.21 |
| [Node.js](https://nodejs.org/) | 20.x |
| [Git](https://git-scm.com/) | 2.x |

### Fastest Path to Deployment

```bash
# 1. Bootstrap Terraform backend (one-time)
./odot-aws-platform/scripts/bootstrap-backend.sh <MGMT_ACCOUNT_ID>

# 2. Configure backend.tf files
./odot-aws-platform/scripts/configure-backend.sh <MGMT_ACCOUNT_ID>

# 3. Deploy all platform stacks
./odot-aws-platform/scripts/deploy-platform.sh

# 4. Collect outputs for app teams
./odot-aws-platform/scripts/collect-stack-outputs.sh

# 5. Onboard a new application
./odot-aws-platform/scripts/onboard-app.sh \
  --app-name "fleet-tracker" \
  --account-type "internal" \
  --github-org "ODOT-GitHub-Org"

# 6. Verify everything
./odot-aws-platform/scripts/verify-prerequisites.sh \
  --app-name "fleet-tracker" \
  --account-type "internal" \
  --stage "dev" \
  --github-org "ODOT-GitHub-Org"
```

For the full step-by-step walkthrough, see [DEPLOYMENT-PREREQUISITES.md](DEPLOYMENT-PREREQUISITES.md).

---

## Automation Scripts

| Script | Purpose |
|--------|---------|
| `bootstrap-backend.sh` | Create S3 state bucket + DynamoDB lock table |
| `configure-backend.sh` | Replace account ID placeholder in all backend.tf files |
| `deploy-platform.sh` | Deploy all stacks in correct dependency order |
| `collect-stack-outputs.sh` | Export Terraform outputs to a single JSON file |
| `onboard-app.sh` | Full app onboarding: repo, tfvars, GitHub vars, branches |
| `verify-prerequisites.sh` | Validate all prerequisites are in place |
| `smoke-test.sh` | Post-deployment health validation |

All scripts live in `odot-aws-platform/scripts/`.

---

## CI/CD Pipeline

### Platform (odot-aws-platform)

Every PR runs:
- **tfsec** — static security analysis (fails on HIGH/CRITICAL)
- **OPA/Conftest** — policy-as-code (tags, SG rules, encryption)
- **Go property tests** — 80+ tests validating module correctness

See [`.github/workflows/platform-ci.yml`](odot-aws-platform/.github/workflows/platform-ci.yml).

### Applications (odot-app-template)

Every push to `dev`/`test`/`prod` runs:
1. **Unit Tests** — halt on failure
2. **Security Scan** — Trivy + Inspector + CodeQL (halt on Critical/High)
3. **Build & Push** — Docker image → ECR (tagged with SHA + branch)
4. **Deploy** — ECS rolling deployment with circuit breaker rollback

Production deploys require manual approval via GitHub Environments.

See [`.github/workflows/ci-cd.yml`](odot-app-template/.github/workflows/ci-cd.yml) and [`.github/workflows/pr-checks.yml`](odot-app-template/.github/workflows/pr-checks.yml).

---

## Security Highlights

- **OIDC federation** — GitHub Actions authenticates to AWS without stored credentials
- **KMS encryption** — all ECR images, CloudWatch logs, and state files encrypted at rest
- **WAF + Shield** — managed rules on all external ALBs
- **Read-only root filesystem** — containers cannot modify their own image at runtime
- **Non-root containers** — all Linux tasks run as UID 1000
- **Scan-on-push** — ECR scans every image on push
- **Security Hub** — FSBP + NIST 800-53 standards enabled
- **GuardDuty + Macie** — threat detection and sensitive data discovery
- **Audit archive** — S3 Object Lock (365-day COMPLIANCE mode) for tamper-evident admin audit logs

---

## Onboarding a New Application

1. Create a repo from the [odot-app-template](odot-app-template/) (click "Use this template" on GitHub)
2. Configure `terraform/terraform.tfvars` with your app settings and platform outputs
3. Run `terraform apply` to provision ECR, ECS service, ALB, and alarms
4. Set GitHub repository variables (`AWS_DEPLOY_ROLE_ARN`, `ECR_REPOSITORY_NAME`, `ECS_CLUSTER_NAME`, `ECS_SERVICE_NAME`)
5. Push to `dev` — the pipeline builds, scans, and deploys automatically

Or use the automated script:

```bash
./odot-aws-platform/scripts/onboard-app.sh \
  --app-name "my-app" \
  --account-type "internal" \
  --github-org "ODOT-GitHub-Org"
```

Full details in [DEPLOYMENT-PREREQUISITES.md § Application Onboarding](DEPLOYMENT-PREREQUISITES.md#9-application-onboarding).

---

## Contributing

- **Platform changes**: See [odot-aws-platform/README.md § Contributing](odot-aws-platform/README.md#contributing)
- **Application development**: See [odot-app-template/CONTRIBUTING.md](odot-app-template/CONTRIBUTING.md)
- **Admin dashboard**: See [admin-dashboard/README.md](admin-dashboard/README.md)

### General Rules

- All Terraform changes must pass `tfsec`, OPA policies, and Go tests before merge
- All application changes must pass unit tests, security scans, and `terraform validate`
- Production deployments require manual approval
- All AWS resources must include `Environment`, `Project`, and `Owner` tags

---

## Support

- **Platform team Slack**: `#odot-platform-support`
- **Alerts (internal apps)**: `#aws-alerts-internal`
- **Alerts (external apps)**: `#aws-alerts-external`

---

## License

Internal use only — Ohio Department of Transportation.
