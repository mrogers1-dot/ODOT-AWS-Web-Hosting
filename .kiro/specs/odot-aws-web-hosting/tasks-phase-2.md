# Phase 2: Security & Compute — GuardDuty, KMS, SCPs, ECS Cluster

## Verification Gate
Run `go test ./...` — all tests from Tasks 1–5 must pass before proceeding to Phase 3.

## Dependencies
Phase 1 must be complete and passing.

---

## Tasks

- [x] 4. Implement `modules/security` — GuardDuty, Security Hub, Config, Macie, KMS, SCPs, Identity Center
  - [x] 4.1 **RED**: Write property test `test/kms_rotation_test.go` — Property 15: All KMS keys have annual key rotation enabled. Use `rapid` to generate `account_type`; assert `aws_kms_key` has `enable_key_rotation = true`. Tag: `// Feature: odot-aws-web-hosting, Property 15`. Test should FAIL. _Validates: Req 9.5_
  - [x] 4.2 **GREEN**: Write `modules/security/main.tf`, `variables.tf`, `outputs.tf`. Create `aws_kms_key` with `enable_key_rotation = true` and alias `alias/odot-{account_type}`. Enable GuardDuty detector with Security Hub publishing. Enable Security Hub with FSBP standard. Enable Config recorder with rules: `vpc-default-security-group-closed`, `iam-no-inline-policy`, `ecs-task-definition-nonroot-user`, `ecs-task-definition-memory-hard-limit`. Enable Macie with S3 classification job. Write SCP JSONs: `scp-internal-no-igw.json`, `scp-external-waf-required.json`. Output `kms_key_arn`, `kms_key_id`, `guardduty_detector_id`. Test from 4.1 should PASS. _Req: 1.2, 1.3, 9.1, 9.2, 9.3, 9.4, 9.5_
  - [x] 4.3 **GREEN**: Configure Identity Center SCP. Write `policies/scp-deny-iam-keys.json` denying `iam:CreateAccessKey` and `iam:CreateLoginProfile`. Add SCP attachment resource. Document that Identity Center permission sets are configured in management account (manual for POC). _Req: 9.7_
  - [x] 4.4 **REFACTOR**: Add inline comments — SCP WAF tag workaround, why IAM keys are denied, Config rule purposes. _Req: 12.5_

- [x] 5. Implement `modules/ecs-cluster` — ECS cluster with Fargate capacity providers
  - [x] 5.1 **RED**: Write property test `test/container_insights_test.go` — Property 14: ECS clusters always have Container Insights enabled. Use `rapid` to generate `cluster_name` and `stage`; assert `setting` block with `containerInsights = enabled`. Tag: `// Feature: odot-aws-web-hosting, Property 14`. Test should FAIL. _Validates: Req 10.1_
  - [x] 5.2 **RED**: Write property test `test/capacity_provider_test.go` — Property 13: Dev and Test ECS services use Fargate Spot. Use `rapid` with `stage` in `["dev", "test"]`; assert `FARGATE_SPOT` with `weight > 0`. Tag: `// Feature: odot-aws-web-hosting, Property 13`. Test should FAIL. _Validates: Req 11.3_
  - [x] 5.3 **GREEN**: Write `modules/ecs-cluster/main.tf`, `variables.tf`, `outputs.tf`. Create `aws_ecs_cluster` with Container Insights enabled. Register `FARGATE` and `FARGATE_SPOT` capacity providers. Dev/Test: `FARGATE_SPOT` weight=1 base=1. Prod: `FARGATE` weight=1. Output `cluster_arn`, `cluster_name`. Tests from 5.1/5.2 should PASS. _Req: 4.1, 4.2, 10.1, 11.3_
  - [x] 5.4 **REFACTOR**: Add inline comments — `base = 1` rationale, Prod on-demand reasoning, Windows fallback note. _Req: 12.5_

---

## Phase 2 Checkpoint

- [x] Run `go test ./...` — all tests from Tasks 1–5 must pass
- [x] Resolve any failures before proceeding to Phase 3
