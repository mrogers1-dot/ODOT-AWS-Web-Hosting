# Phase 5: Stacks & Integration — Wire Modules into 6 Deployable Stacks

## Verification Gate
Run `go test ./...` — ALL platform module and stack tests must pass before proceeding to Phase 6.

## Dependencies
Phase 4 must be complete and passing (all modules must exist before wiring into stacks).

---

## Tasks

- [x] 11. Implement stack configurations — wire modules into six deployable stacks
  - [x] 11.1 **RED**: Write unit test asserting all six stacks call required modules (`networking`, `ecs-cluster`, `security`, `monitoring`, `oidc`). Assert external stacks pass `waf_acl_arn`. Test should FAIL. _Req: 1.1, 8.1, 8.3_
  - [x] 11.2 **GREEN**: Write `stacks/internal-dev/main.tf` and `terraform.tfvars`. Call networking (internal, dev), ecs-cluster, security, monitoring, oidc. _Req: 1.1, 8.3_
  - [x] 11.3 **GREEN**: Write `stacks/internal-test/main.tf` and `stacks/internal-prod/main.tf`. Mirror internal-dev with appropriate stage values. Prod: FARGATE primary. _Req: 1.1, 8.3_
  - [x] 11.4 **GREEN**: Write `stacks/external-dev/main.tf`, `stacks/external-test/main.tf`, `stacks/external-prod/main.tf`. Call networking (external), ecs-cluster, security, monitoring, oidc. Pass `waf_acl_arn`. Test from 11.1 should PASS. _Req: 1.1, 3.3, 8.3_
  - [x] 11.5 **GREEN**: Write `stacks/*/provider.tf` for all six stacks. Configure `aws` provider with `assume_role` per account. Use provider aliases. _Req: 8.1_
  - [x] 11.6 **REFACTOR**: Verify naming convention `{Project}-{Environment}`, add comments on provider alias pattern. _Req: 8.7, 12.5_

- [x] 13. Integration checkpoint — Verify all platform tests pass
  - [x] 13.1 Run `go test ./...` — all tests from Tasks 1–12 must pass
  - [x] 13.2 Resolve any failures before proceeding

---

## Phase 5 Checkpoint

- [x] Run `go test ./...` — ALL module and stack tests pass
- [x] `terraform validate` succeeds on all six stacks
- [x] Resolve any failures before proceeding to Phase 6
