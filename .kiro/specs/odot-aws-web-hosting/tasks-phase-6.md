# Phase 6: App Template & Docs — CI/CD Template, Platform Docs, Smoke Tests

## Verification Gate
Full platform checkpoint: all Go tests pass, smoke test script exists and is valid, documentation is complete.

## Dependencies
Phase 5 must be complete and passing (stacks must be wired before template can reference them).

---

## Tasks

- [x] 14. Implement `odot-app-template` repository
  - [x] 14.1 **RED**: Write validation test for app-template structure. Assert required files exist (`ci-cd.yml`, `pr-checks.yml`, `terraform/main.tf`, `terraform/variables.tf`, `terraform.tfvars.example`, `Dockerfile`, `CONTRIBUTING.md`, `README.md`). Assert `ci-cd.yml` contains `role-to-assume` and NOT `AWS_ACCESS_KEY_ID`. Assert `timeout-minutes` ≤ 15 on non-prod jobs. Assert job dependency chain: `scan` has `needs: [unit-test]`, `build-push` has `needs: [scan]`, deploy jobs have `needs: [build-push]` — ensuring unit test failure halts all downstream stages. Assert `deploy-prod` job includes `environment: production` to enforce manual approval gate. Test should FAIL. _Req: 6.2, 6.7, 6.8, 6.9, 7.1, 7.2_
  - [x] 14.2 **GREEN**: Create `odot-app-template` structure. Create `.github/workflows/ci-cd.yml` and `pr-checks.yml` (triggers on `pull_request` to dev/test/prod; runs linting and unit tests only — no image build, no scan, no deploy). Create `terraform/main.tf`, `variables.tf`, `terraform.tfvars.example`. Create `Dockerfile` stub (multi-stage, non-root, minimal base). _Req: 7.1, 7.2, 7.3, 7.4_
  - [x] 14.3 **GREEN**: Write `ci-cd.yml` workflow. Trigger on push to dev/test/prod. Jobs: `unit-test` → `scan` (Trivy+Inspector+CodeQL) → `build-push` (ECR tag SHA + branch-latest) → `deploy-dev`/`deploy-test` (timeout-minutes: 15) / `deploy-prod` (manual approval via `environment: production`). OIDC auth via `aws-actions/configure-aws-credentials@v4`. Test from 14.1 should PASS. _Req: 6.1–6.9_
  - [x] 14.4 **GREEN**: Write `CONTRIBUTING.md` and `README.md`. Explain routes, Dockerfile updates, deployment triggers, Terraform variables. _Req: 7.6, 12.4_
  - [x] 14.5 **REFACTOR**: Review template for developer experience — clear variable comments, security best practices in Dockerfile, workflow YAML comments. _Req: 7.6, 12.5_

- [x] 15. Write documentation for `odot-aws-platform`
  - [x] 15.1 **RED**: Write validation test for documentation completeness. Assert `README.md` contains: architecture overview, module layout, apply/destroy instructions, capacity planning, module versioning. Assert `docs/runbook.md` exists with onboarding/alarm/KMS/notification sections. Assert `docs/architecture/` has three diagram files. Test should FAIL. _Req: 12.1, 12.2, 12.3_
  - [x] 15.2 **GREEN**: Write `README.md`. Architecture, account structure, module layout, terraform commands, module versioning workflow, capacity planning (ALB target groups/ALB=100, ECS services/cluster=5000, IPs per /16=65k, theoretical max, limits needing increases). _Req: 7.5, 8.6, 12.1_
  - [x] 15.3 **GREEN**: Write `docs/runbook.md`. Onboarding via App_Template, responding to CloudWatch alarms, rotating KMS keys, adding Notification_Channels. _Req: 12.2_
  - [x] 15.4 **GREEN**: Write `docs/architecture/network-topology.md`, `cicd-pipeline.md`, `ecs-cluster-layout.md` (Mermaid diagrams). Test from 15.1 should PASS. _Req: 12.3_
  - [x] 15.5 **REFACTOR**: Review docs for consistency with implemented Terraform, actionable runbook procedures, accurate capacity numbers. _Req: 12.1, 12.2, 12.3_

- [x] 16. Write smoke test and destroy validation scripts
  - [x] 16.1 **RED**: Write test asserting `scripts/smoke-test.sh` exists and is executable. Test should FAIL.
  - [x] 16.2 **GREEN**: Write `scripts/smoke-test.sh` accepting `{account} {stage}` args. Assert: 6 ECS clusters exist, GuardDuty enabled, Security Hub FSBP active, Budgets alert at $800, 6 dashboards exist, workflow YAML has `role-to-assume` (no `AWS_ACCESS_KEY_ID`), workflow has `timeout-minutes` ≤ 15, `odot-app-template` is template repo. SCP enforcement: attempt IGW creation in internal → assert AccessDenied; attempt internet-facing ALB without WAF tag in external → assert AccessDenied. Shield Standard: for each External ALB, call `aws shield describe-protection` and assert protection is active. Test from 16.1 should PASS. _Req: 1.4, 1.5, 3.4, 6.9, 9.1, 9.2, 10.2, 11.1, 13.1–13.4_
  - [x] 16.3 **REFACTOR**: Add colored pass/fail output, `--help` flag, graceful credential error handling. _Req: 12.5_
  - [x] 16.4 **RED**: Write integration test `test/integration/destroy_test.go` asserting that after `terraform destroy` completes on a sandbox stack, no orphaned resources remain (ENIs, security groups, log groups, ECR repos, KMS key aliases tagged with the stack's `Project` + `Environment`). Test should FAIL because no destroy validation script exists. _Req: 8.4_
  - [x] 16.5 **GREEN**: Implement destroy validation in `scripts/validate-destroy.sh` — accepts `{account} {stage}`, runs `terraform destroy -auto-approve`, then queries AWS for any resources still tagged with `Project=ODOTWebHosting` + `Environment={stage}`. Reports orphaned resources and exits non-zero if any found. Wire into `test/integration/destroy_test.go`. Test from 16.4 should PASS. _Req: 8.4_

- [x] 17. Final platform checkpoint — Verify all platform tests pass
  - [x] 17.1 Run `go test ./...` — ALL property and unit tests must pass
  - [x] 17.2 Run `scripts/smoke-test.sh` against deployed environment (if available)
  - [x] 17.3 Resolve any failures

---

## Phase 6 Checkpoint

- [x] All Go tests pass (`go test ./...`)
- [x] Smoke test script is valid and executable
- [x] Documentation validation test passes
- [x] Platform is feature-complete for core hosting (no dashboard yet)
- [x] Resolve any failures before proceeding to Phase 7
