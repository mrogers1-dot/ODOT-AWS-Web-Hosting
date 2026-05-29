# Contributing to ODOT Web Applications

This guide explains how to develop, configure, and deploy web applications using the ODOT App Template. It covers adding routes, updating the Dockerfile, triggering deployments, configuring Terraform, and troubleshooting common issues.

---

## Table of Contents

- [Branch Strategy](#branch-strategy)
- [Adding New Routes and Endpoints](#adding-new-routes-and-endpoints)
- [Updating the Dockerfile](#updating-the-dockerfile)
- [Triggering Deployments](#triggering-deployments)
- [Setting Terraform Variables](#setting-terraform-variables)
- [Pull Request Process](#pull-request-process)
- [Troubleshooting](#troubleshooting)
- [HTTPS and Custom Domains](#https-and-custom-domains)
- [Enabling Distributed Tracing](#enabling-distributed-tracing)

---

## Branch Strategy

The ODOT platform uses a promotion-based branching model:

```
feature/* ──► dev ──► test ──► prod
```

| Branch | Environment | Deploy Type | Approval |
|--------|-------------|-------------|----------|
| `dev` | Development | Automatic | None |
| `test` | Testing/QA | Automatic | None |
| `prod` | Production | Manual gate | Required |

### Workflow

1. Create a feature branch from `dev` (e.g., `feature/add-user-endpoint`).
2. Develop and test locally.
3. Open a PR targeting `dev`. PR checks (lint, unit tests, Terraform validate) must pass.
4. Merge to `dev` — triggers automatic deployment to the Dev environment.
5. When ready for QA, merge `dev` into `test` — triggers automatic deployment to Test.
6. When approved for production, merge `test` into `prod` — triggers deployment with manual approval gate.

### Rules

- Never push directly to `prod`. All production changes must flow through `dev` → `test` → `prod`.
- Feature branches should be short-lived (< 1 week).
- Keep `dev`, `test`, and `prod` branches protected — require PR reviews before merge.

---

## Adding New Routes and Endpoints

### Node.js (Express)

Add routes in your application source. For example, in `server.js` or a dedicated routes file:

```javascript
// routes/users.js
const express = require('express');
const router = express.Router();

router.get('/users', (req, res) => {
  res.json({ users: [] });
});

router.get('/users/:id', (req, res) => {
  res.json({ id: req.params.id });
});

module.exports = router;
```

Register the route in your main application file:

```javascript
// server.js
const usersRouter = require('./routes/users');
app.use('/api', usersRouter);
```

### Python (Flask/FastAPI)

```python
# routes/users.py
from flask import Blueprint, jsonify

users_bp = Blueprint('users', __name__)

@users_bp.route('/users', methods=['GET'])
def list_users():
    return jsonify({"users": []})
```

### .NET

```csharp
// Controllers/UsersController.cs
[ApiController]
[Route("api/[controller]")]
public class UsersController : ControllerBase
{
    [HttpGet]
    public IActionResult GetUsers() => Ok(new { users = Array.Empty<object>() });
}
```

### Important Considerations

- **Health check endpoint**: Always keep a `/health` endpoint available. The ALB uses it for target group health checks. The Dockerfile `HEALTHCHECK` and ALB target group both reference this path.
- **Port consistency**: New routes are served on the same port defined in `container_port` (default: 8080). Do not start additional listeners on different ports.
- **Read-only filesystem**: The container runs with a read-only root filesystem. If your route needs to write temporary files, use `/tmp` (the only writable path in Fargate tasks with read-only root).

---

## Updating the Dockerfile

The template provides a multi-stage Dockerfile. Here's how to customize it for common scenarios.

### Changing the Base Image

Edit the `FROM` lines in the Dockerfile:

```dockerfile
# For Python applications
FROM python:3.12-slim AS build
# ...
FROM python:3.12-slim AS production

# For .NET applications
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
# ...
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS production

# For Java applications
FROM eclipse-temurin:21-jdk AS build
# ...
FROM eclipse-temurin:21-jre-alpine AS production
```

### Adding System Dependencies

Add `RUN` commands in the build stage before copying application code:

```dockerfile
FROM node:20-alpine AS build

# Add system dependencies
RUN apk add --no-cache \
    python3 \
    make \
    g++

WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
```

### Windows Containers

For .NET Framework / IIS applications, use a Windows base image:

```dockerfile
FROM mcr.microsoft.com/dotnet/framework/sdk:4.8 AS build
WORKDIR /app
COPY . .
RUN msbuild /p:Configuration=Release

FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8 AS production
COPY --from=build /app/bin/Release /inetpub/wwwroot
```

> **Note**: Windows containers require `runtime = "windows"` in `terraform.tfvars` and minimum `cpu = 1024`. The `readonlyRootFilesystem` setting is not supported on Windows containers.

### Key Rules

1. **Always use a non-root user** (UID 1000) in the production stage for Linux containers.
2. **Keep the `HEALTHCHECK` instruction** — ECS uses it alongside ALB health checks.
3. **Expose only one port** — must match `container_port` in your Terraform variables.
4. **Use multi-stage builds** — keep build tools out of the production image to reduce attack surface.
5. **Pin base image versions** — use specific tags (e.g., `node:20-alpine`) rather than `latest`.

---

## Triggering Deployments

Deployments are triggered automatically by pushing to protected branches.

### Automatic Deployment (Dev/Test)

```bash
# Deploy to Dev
git checkout dev
git merge feature/my-feature
git push origin dev

# Deploy to Test
git checkout test
git merge dev
git push origin test
```

### Production Deployment (Manual Approval)

```bash
# Deploy to Prod (triggers manual approval gate)
git checkout prod
git merge test
git push origin prod
```

After pushing to `prod`, a GitHub Actions reviewer must approve the deployment in the repository's Actions tab. The approval gate uses GitHub Environments — authorized approvers are configured in the repository settings.

### Pipeline Stages

Each deployment runs through these stages in order:

1. **Unit Tests** — application tests must pass
2. **Security Scan** — Trivy (container vulnerabilities), Amazon Inspector (SBOM analysis), CodeQL (source code)
3. **Build & Push** — Docker image built and pushed to ECR (tagged with commit SHA and `{branch}-latest`)
4. **Deploy** — ECS rolling deployment (zero-downtime)

If any stage fails, the pipeline halts and no deployment occurs.

### Re-triggering a Deployment

If a deployment fails due to a transient issue (network timeout, AWS throttling):

```bash
# Push an empty commit to re-trigger
git commit --allow-empty -m "ci: re-trigger deployment"
git push origin dev
```

### Rollback

ECS has circuit breaker enabled. If the new task fails health checks, ECS automatically rolls back to the previous task definition. For manual rollback:

```bash
# Revert the last commit and push
git revert HEAD
git push origin dev
```

---

## Setting Terraform Variables

When onboarding a new application, you need to configure Terraform variables.

### Step 1: Copy the Example File

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

### Step 2: Set Application Variables

These are the variables you control:

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `app_name` | Yes | Unique app identifier (lowercase, hyphens) | `"fleet-tracker"` |
| `runtime` | No | `"linux"` or `"windows"` (default: `"linux"`) | `"linux"` |
| `container_port` | No | Port your app listens on (default: 8080) | `3000` |
| `cpu` | No | Fargate CPU units (default: 256) | `512` |
| `memory` | No | Fargate memory in MiB (default: 512) | `1024` |

### Step 3: Get Infrastructure Variables from the Platform Team

These values come from the shared platform infrastructure:

| Variable | How to Obtain |
|----------|---------------|
| `account_type` | `"internal"` for corporate apps, `"external"` for public-facing |
| `stage` | Set to `"dev"` initially; CI/CD handles test/prod |
| `vpc_id` | Platform team provides per account-stage |
| `private_subnet_ids` | Platform team provides (minimum 2 AZs) |
| `alb_subnet_ids` | Platform team provides |
| `cluster_arn` | Platform team provides per account-stage |
| `cluster_name` | Platform team provides (e.g., `"WebHosting-Dev"`) |
| `kms_key_arn` | Platform team provides per account |
| `sns_topic_arn` | Platform team provides per account |
| `waf_acl_arn` | Required for external account; empty string for internal |
| `domain_name` | Your app's FQDN (e.g., `"fleet-tracker.dev.odot.ohio.gov"`) |
| `hosted_zone_id` | Route 53 hosted zone ID — platform team provides |
| `certificate_arn` | Leave empty to auto-create via ACM DNS validation |

### Step 4: Initialize and Apply

```bash
cd terraform
terraform init
terraform plan    # Review the resources that will be created
terraform apply   # Provision ECR, ECS service, ALB, alarms, IAM roles
```

### CPU/Memory Combinations

| CPU (units) | Valid Memory (MiB) |
|-------------|-------------------|
| 256 | 512, 1024, 2048 |
| 512 | 1024, 2048, 3072, 4096 |
| 1024 | 2048, 3072, 4096, 5120, 6144, 7168, 8192 |
| 2048 | 4096 – 16384 (in 1024 increments) |
| 4096 | 8192 – 30720 (in 1024 increments) |

> **Windows containers** require minimum `cpu = 1024`.

---

## Pull Request Process

### Before Opening a PR

1. Run tests locally:
   ```bash
   npm test          # or pytest, dotnet test, etc.
   ```
2. Validate Terraform (if you changed infrastructure config):
   ```bash
   cd terraform
   terraform fmt -check -recursive
   terraform init -backend=false
   terraform validate
   ```
3. Build the Docker image locally:
   ```bash
   docker build -t my-app:local .
   docker run -p 8080:8080 my-app:local
   # Verify http://localhost:8080/health returns 200
   ```

### PR Checks

When you open a PR, the following automated checks run:

| Check | What It Does |
|-------|--------------|
| **Lint** | Runs language-specific linter (ESLint, ruff, dotnet format) |
| **Unit Tests** | Runs your test suite |
| **Terraform Validate** | Checks `terraform fmt` and `terraform validate` |

All checks must pass before the PR can be merged.

### Review Requirements

- At least one approving review is required.
- The PR author cannot approve their own PR.
- Resolve all review comments before merging.

---

## Troubleshooting

### Pipeline Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| Unit tests fail | Code regression | Fix failing tests, push again |
| Trivy finds Critical/High vulnerability | Vulnerable dependency in image | Update the dependency or base image |
| Inspector scan fails | SBOM contains known CVE | Update affected package |
| Docker build fails | Dockerfile syntax or missing files | Check `COPY` paths and build context |
| ECR push fails | OIDC role lacks permissions | Contact platform team to verify IAM role |
| ECS deploy fails | Container crashes on startup | Check CloudWatch logs at `/ecs/{app_name}/{stage}` |

### Container Startup Issues

If your container fails to start after deployment:

1. **Check CloudWatch Logs**:
   ```bash
   aws logs tail /ecs/{app_name}/{stage} --follow
   ```

2. **Common causes**:
   - Application crashes on startup (check for missing env vars)
   - Port mismatch between app and `container_port`
   - Read-only filesystem violation (write to `/tmp` instead)
   - Health check failing (ensure `/health` endpoint returns 200)

3. **ECS will auto-rollback** if the new task fails health checks (circuit breaker enabled).

### Terraform Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `terraform init` fails | Backend not configured | Uncomment and fill in `backend "s3"` block in `main.tf` |
| State lock error | Previous apply was interrupted | Ask platform team to release the DynamoDB lock |
| Module source error | Can't reach `odot-aws-platform` repo | Check GitHub access token / SSH key |
| Validation error on `app_name` | Invalid characters | Use only lowercase letters, numbers, and hyphens (3-30 chars) |

### Health Check Failures

The ALB health check expects:
- **Path**: `/health`
- **Port**: Same as `container_port`
- **Expected response**: HTTP 200
- **Interval**: 30 seconds
- **Timeout**: 5 seconds
- **Healthy threshold**: 3 consecutive successes
- **Unhealthy threshold**: 3 consecutive failures

If health checks fail, verify your application responds to `GET /health` with a 200 status code on the configured port.

### Permission Issues

- **"Access Denied" on ECR push**: The GitHub Actions OIDC role may not have permission for your repository. Contact the platform team.
- **"Access Denied" on ECS update**: Verify the OIDC role has `ecs:UpdateService` permission scoped to your cluster.
- **Cannot create resources in Internal Account**: Internet-facing resources are blocked by SCP. Internal apps must use private ALBs only.

---

## HTTPS and Custom Domains

All applications are served over HTTPS by default. HTTP requests are automatically redirected to HTTPS (301).

### How TLS Works

- The platform provisions an ACM certificate for your `domain_name` automatically via DNS validation
- The ALB terminates TLS using a modern security policy (TLS 1.3)
- Traffic between the ALB and your container travels over the VPC-internal network (unencrypted but private)
- A Route 53 alias record points your domain to the ALB

### What You Need to Do

1. Set `domain_name` in your `terraform.tfvars` (e.g., `"fleet-tracker.dev.odot.ohio.gov"`)
2. Set `hosted_zone_id` (the platform team provides this)
3. Run `terraform apply` — the certificate is created and validated automatically
4. Wait 5–30 minutes for ACM DNS validation to complete on first deploy

### Testing Locally

Your app doesn't need to handle TLS itself — the ALB does that. Locally, test on HTTP:

```bash
docker run -p 8080:8080 my-app:local
curl http://localhost:8080/health  # This is fine for local testing
```

---

## Enabling Distributed Tracing

The platform supports AWS X-Ray distributed tracing via an ADOT (AWS Distro for OpenTelemetry) sidecar. This is opt-in per application.

### Enable Tracing

Set `enable_tracing = true` in your `terraform.tfvars`:

```hcl
enable_tracing = true
```

Run `terraform apply` — this adds an ADOT collector sidecar to your task definition.

### Instrument Your Application

#### Node.js

```bash
npm install @opentelemetry/api @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node
```

```javascript
// tracing.js — require this FIRST in your entry point
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');

const sdk = new NodeSDK({
  instrumentations: [getNodeAutoInstrumentations()],
});
sdk.start();
```

```javascript
// server.js
require('./tracing'); // Must be first!
const express = require('express');
// ... rest of your app
```

#### Python

```bash
pip install opentelemetry-distro opentelemetry-exporter-otlp
opentelemetry-bootstrap -a install
```

```bash
# In your Dockerfile CMD or entrypoint:
CMD ["opentelemetry-instrument", "python", "app.py"]
```

#### .NET

```bash
dotnet add package OpenTelemetry.Extensions.Hosting
dotnet add package OpenTelemetry.Instrumentation.AspNetCore
dotnet add package OpenTelemetry.Exporter.OpenTelemetryProtocol
```

```csharp
builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()
        .AddOtlpExporter());
```

### Environment Variables (Set Automatically)

When tracing is enabled, the ADOT sidecar is configured to receive traces on `localhost:4317` (gRPC) and `localhost:4318` (HTTP). Your app's OTEL SDK should export to these endpoints by default.

### Viewing Traces

Traces are available in the AWS X-Ray console:
1. Go to **CloudWatch → X-Ray traces → Trace map**
2. Filter by service name (your `app_name`)
3. Click individual traces to see the full request path and latency breakdown

---

## Getting Help

- **Platform team Slack**: `#odot-platform-support`
- **Alerts channel (internal)**: `#aws-alerts-internal`
- **Alerts channel (external)**: `#aws-alerts-external`
- **Platform repository**: `odot-aws-platform` — contains all Terraform modules and documentation
