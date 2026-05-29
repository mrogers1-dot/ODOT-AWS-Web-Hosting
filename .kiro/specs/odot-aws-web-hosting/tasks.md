# Implementation Plan: ODOT AWS Web Hosting POC

## Overview

This plan converts the ODOT AWS Web Hosting design into incremental coding tasks using **Red/Green/Refactor** methodology. Each task follows the cycle: RED (write a failing test), GREEN (minimal implementation to pass), REFACTOR (improve while keeping tests green). All infrastructure is Terraform (HCL), all tests are Go (Terratest + rapid), and all CI/CD is GitHub Actions YAML.

## Phased Execution Strategy

Tasks are split into **7 phase files** organized by logical completion points. Each phase should be run, tested, and verified before proceeding to the next. This avoids cascading failures and keeps sessions focused.

| Phase | File | Scope | Verification Gate |
|-------|------|-------|-------------------|
| 1 | `tasks-phase-1.md` | Foundation: Repo structure, OIDC, Networking | `go test ./...` — Tasks 1-3 pass |
| 2 | `tasks-phase-2.md` | Security & Compute: GuardDuty, KMS, SCPs, ECS Cluster | `go test ./...` — Tasks 4-5 pass |
| 3 | `tasks-phase-3.md` | Application Service: ECR, ECS Service, ALB, Auto-scaling, Alarms | `go test ./...` — Tasks 7 pass |
| 4 | `tasks-phase-4.md` | Monitoring & Utilities: CloudWatch, Budgets, Scanner Gate, Versioning | `go test ./...` — Tasks 9-12 pass |
| 5 | `tasks-phase-5.md` | Stacks & Integration: Wire modules into 6 deployable stacks | `go test ./...` — All platform tests pass |
| 6 | `tasks-phase-6.md` | App Template & Docs: CI/CD template, Platform docs, Smoke tests | Full platform checkpoint |
| 7 | `tasks-phase-7.md` | Admin Dashboard: Infra, Backend, Frontend, Deploy, Docs | Final full-system checkpoint |
| 8 | `tasks-phase-8.md` | Connectivity & TLS: VPC Endpoints, HTTPS, ALB Access Logs | P16-P18 pass, stacks validate |
| 9 | `tasks-phase-9.md` | Security Hardening: WAF Rules, NIST, Secrets, IaC Scanning, Tags | P19-P22 pass, platform CI green |
| 10 | `tasks-phase-10.md` | Resilience & Observability: FIS, Scaling Model, Canaries, Tracing | P23 pass, FIS/canary validate |
| 11 | `tasks-phase-11.md` | Dashboard Upgrades: Real-Time SSE, Tamper-Evident Audit | P24 pass, SSE compiles, final checkpoint |

---

## Cross-Cutting Standards

- **Inline Terraform comments (Requirement 12.5)**: All Terraform files MUST include inline comments on non-obvious resource configurations explaining the purpose and any constraints. This applies to every REFACTOR step across all tasks.

## Deferred Items (Post-POC)

- **Requirement 5.4 — Registry-level Inspector scanning**: Pipeline gate (Task 14.3) covers intent. Registry-level `aws_inspector2_enabler` with ECR resource type is a future hardening item for images pushed outside the pipeline. Circle back post-POC.
- **Requirement 11.4 — Savings Plans**: Require 1–2 months of baseline usage data to right-size commitment. Evaluate and purchase after POC establishes usage patterns.
- **Requirement 14 Phase 2 — Advanced Dashboard Features**: CloudWatch RUM for real user metrics, ECS Exec (shell into container), promote image across stages, update env vars from UI, trigger pipeline re-run.

## Testing Notes

- Property tests (P1–P15) operate on `terraform plan` JSON output — no AWS credentials required
- Integration tests require a sandbox AWS account: `go test ./integration/... -v -timeout 30m`
- Smoke tests (Task 16) require deployed environment credentials
- Windows Fargate: Property 3 exempts `readonlyRootFilesystem`; Property 13 applies to Linux only
- All Go test files must include tag: `// Feature: odot-aws-web-hosting, Property {N}: {text}`
- Time-bound SLA requirements (Req 9.9: Security Hub notification within 5 min, Req 10.7: ECS task exit notification within 2 min) are validated exclusively during integration testing — they depend on AWS event propagation latency and cannot be unit tested. The EventBridge rules and SNS routing are verified structurally in Task 9.1/9.2; the end-to-end timing is confirmed by manually stopping a task and observing Slack delivery during integration test runs.

## Requirements Traceability Matrix

| Requirement | Tasks |
|---|---|
| 1.1 | 11.2–11.4 |
| 1.2, 1.3 | 4.2 |
| 1.4, 1.5 | 16.2 |
| 1.6 | 7.16, 7.17 |
| 2.1, 2.3, 2.4 | 3.1–3.3 |
| 2.2 | 3.4 |
| 2.5 | 4.2 (SCP denies IGW — see design note on layered defense) |
| 3.1, 3.2 | 3.3 |
| 3.3, 3.4, 3.5 | 7.7, 7.8, 16.2 |
| 4.1, 4.2 | 5.3, 7.15 |
| 4.3 | 7.14, 7.15 |
| 4.4–4.6 | 7.9, 7.10 |
| 4.7 | 7.5, 7.6 |
| 4.8 | 7.4, 7.6 |
| 5.1–5.3 | 7.1, 7.3 |
| 5.4 | 14.3 (deferred registry-level) |
| 5.5 | 7.2, 7.3 |
| 6.1–6.9 | 14.1, 14.3, 12.1–12.4, 16.2 |
| 7.1–7.4 | 14.1–14.2 |
| 7.5 | 15.2 |
| 7.6 | 14.4 |
| 8.1 | 11.5 |
| 8.2 | 1.2 |
| 8.3 | 11.2–11.4 |
| 8.4 | 16.4, 16.5 |
| 8.5 | 1.1, 1.2 |
| 8.6 | 10.1–10.3 |
| 8.7 | 11.6 |
| 9.1–9.4 | 4.2 |
| 9.5 | 4.1, 4.2 |
| 9.6 | 2.1, 2.2 |
| 9.7 | 4.3 |
| 9.8 | 7.4, 7.6 |
| 9.9 | 9.2 |
| 10.1 | 5.1, 5.3 |
| 10.2 | 9.2 |
| 10.3 | 7.12, 7.13 |
| 10.4, 10.5 | 9.2 |
| 10.6 | 7.11, 7.13 |
| 10.7 | 9.1, 9.2 (timing validated in integration tests) |
| 11.1, 11.2 | 9.2 |
| 11.3 | 5.2, 5.3 |
| 11.4 | Deferred post-POC |
| 11.5 | 7.16, 7.17 |
| 12.1 | 15.2 |
| 12.2 | 15.3 |
| 12.3 | 15.4 |
| 12.4 | 14.4 |
| 12.5 | All REFACTOR steps |
| 13.1–13.4 | 16.2 |
| 14.1 | 18.2, 19.2, 20.2 |
| 14.2, 14.3 | 18.2, 19.2, 19.12 |
| 14.4 | 22.3, 22.4, 22.5 |
| 14.5, 14.6 | 20.2, 21.2, 21.3, 21.4 |
| 14.7–14.10 | 20.3 |
| 14.11–14.15 | 19.4, 20.4 |
| 14.16, 14.17 | 19.3, 19.12, 20.5, 20.6 |
| 14.18, 14.19 | 18.3, 19.11 |
| 14.20, 14.21 | 19.3, 19.4, 19.5, 20.5, 20.7, 20.8 |
| 14.22, 14.23 | 19.3, 19.7, 20.8 |
| 14.24 | 19.5, 20.5 |
| 14.25 | 19.6, 20.5 |
| 14.26 | 19.8, 20.5 |
| 14.27 | 19.10, 20.5 |
| 14.28 | 19.12 |
| 14.29, 14.30 | 18.4, 19.9 |
| 14.31 | 22.7 |
| 14.32 | 22.8 |
| 14.33 | 22.9 |
| 14.34 | 22.10 |
| 14.35 | 22.2–22.6 |
