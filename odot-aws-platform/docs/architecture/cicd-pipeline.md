# CI/CD Pipeline Flow — ODOT AWS Web Hosting

This diagram shows the full CI/CD pipeline triggered by GitHub Enterprise Actions. The pipeline builds, scans, and deploys containerized applications to ECS Fargate clusters. It uses OIDC authentication (no stored credentials), mandatory vulnerability scanning, and a manual approval gate for production deployments.

```mermaid
flowchart TD
    %% ─── Trigger ────────────────────────────────────────────────────────────
    Push["Developer pushes to\ndev / test / prod branch"]

    %% ─── Stage 1: Unit Tests ────────────────────────────────────────────────
    Push --> UnitTest["Stage 1: Unit Tests\n(application test suite)"]
    UnitTest -->|"❌ Tests fail"| HaltTests["Pipeline Halted\nFailure report to developer"]

    %% ─── Stage 2: Security Scanning ─────────────────────────────────────────
    UnitTest -->|"✅ Tests pass"| Scan["Stage 2: Security Scanning"]

    subgraph ScanTools["Parallel Scanners"]
        Trivy["Trivy\nContainer Image Scan\n(CRITICAL/HIGH → fail)"]
        Inspector["Amazon Inspector\nSBOM Vulnerability Scan\n(CRITICAL/HIGH → fail)"]
        CodeQL["CodeQL\nSource Code Analysis\n(High severity → fail)"]
    end

    Scan --> Trivy
    Scan --> Inspector
    Scan --> CodeQL

    Trivy --> ScanGate{"Scanner Gate\nAny CRITICAL/HIGH?"}
    Inspector --> ScanGate
    CodeQL --> ScanGate

    ScanGate -->|"❌ Vulnerability found"| BlockDeploy["Deployment Blocked\nRemediation guidance provided\nImage NOT pushed to ECR"]

    %% ─── Stage 3: Build & Push ──────────────────────────────────────────────
    ScanGate -->|"✅ All scans clean"| Build["Stage 3: Docker Build\n(multi-stage, non-root)"]
    Build --> ECRPush["Push to ECR\nTags: {commit-SHA}\n       {branch}-latest"]

    %% ─── Stage 4: Deploy ────────────────────────────────────────────────────
    ECRPush --> BranchCheck{"Which branch?"}

    BranchCheck -->|"dev"| DeployDev["Deploy to Dev\nECS Rolling Update"]
    BranchCheck -->|"test"| DeployTest["Deploy to Test\nECS Rolling Update"]
    BranchCheck -->|"prod"| ApprovalGate["Manual Approval Gate\n(GitHub Environment)"]

    ApprovalGate -->|"✅ Approved"| DeployProd["Deploy to Prod\nECS Rolling Update"]
    ApprovalGate -->|"❌ Rejected / Timeout (7d)"| Cancelled["Deployment Cancelled"]

    DeployDev --> Done["Deployment Complete\nZero-downtime rolling update"]
    DeployTest --> Done
    DeployProd --> Done

    %% ─── Authentication ─────────────────────────────────────────────────────
    subgraph Auth["Authentication (all AWS jobs)"]
        OIDC["GitHub OIDC → AWS STS\nAssumeRoleWithWebIdentity\nNo stored credentials"]
    end

    ECRPush -.->|"uses"| Auth
    DeployDev -.->|"uses"| Auth
    DeployTest -.->|"uses"| Auth
    DeployProd -.->|"uses"| Auth
```

## Pipeline Stages Summary

| Stage | Purpose | Failure Behavior |
|-------|---------|-----------------|
| **1. Unit Tests** | Validate application logic | Pipeline halts; no image built |
| **2. Security Scan** | Trivy + Inspector + CodeQL | Pipeline halts; image not pushed to ECR; remediation guidance provided |
| **3. Build & Push** | Docker build + ECR push | Pipeline halts on build failure |
| **4. Deploy** | ECS rolling update | ECS circuit breaker auto-rolls back on failure |

## Key Design Points

- **OIDC Authentication**: GitHub Actions uses `aws-actions/configure-aws-credentials@v4` with OIDC — no `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` stored in secrets.
- **Scanner Gate**: Any CRITICAL or HIGH severity finding from Trivy, Inspector, or CodeQL blocks the deployment. MEDIUM/LOW/INFORMATIONAL findings are reported but do not block.
- **Image Tagging**: Every image receives two tags — the full Git commit SHA (immutable) and `{branch}-latest` (mutable pointer).
- **Production Approval**: Prod deployments require manual approval via GitHub Environments. Approval requests expire after 7 days.
- **Zero-Downtime**: ECS rolling deployments ensure no service interruption. Circuit breaker is enabled for automatic rollback on failure.
- **SLA**: Full build-scan-deploy cycle completes within 15 minutes for non-prod stages.
