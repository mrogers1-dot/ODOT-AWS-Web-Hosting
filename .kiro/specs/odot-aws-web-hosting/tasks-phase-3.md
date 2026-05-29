# Phase 3: Application Service — ECR, ECS Service, ALB, Auto-scaling, Alarms

## Verification Gate
Run `go test ./...` — all tests from Tasks 1–7 must pass before proceeding to Phase 4.

## Dependencies
Phase 2 must be complete and passing (ECS cluster module, security/KMS module required by app-service).

---

## Tasks

- [x] 7. Implement `modules/app-service` — ECR, ECS service, ALB, auto-scaling, alarms
  - [x] 7.1 **RED**: Write property test `test/ecr_config_test.go` — Property 4: All ECR repositories have scan-on-push enabled and KMS encryption. Use `rapid` to generate `app_name`, `account_type`; assert `scan_on_push = true` and `encryption_type = "KMS"` with non-null `kms_key`. Tag: `// Feature: odot-aws-web-hosting, Property 4`. Test should FAIL. _Validates: Req 5.2, 5.3_
  - [x] 7.2 **RED**: Write property test `test/ecr_lifecycle_test.go` — Property 5: ECR lifecycle policies enforce correct retention. Use `rapid` to generate `app_name`; assert exactly two rules: tagged `countNumber = 10`, untagged `countNumber = 7`. Tag: `// Feature: odot-aws-web-hosting, Property 5`. Test should FAIL. _Validates: Req 5.5_
  - [x] 7.3 **GREEN**: Write `modules/app-service/ecr.tf`. Create `aws_ecr_repository` with scan-on-push and KMS encryption. Create lifecycle policy with two rules. Tests from 7.1/7.2 should PASS. _Req: 5.1, 5.2, 5.3, 5.5_
  - [x] 7.4 **RED**: Write property test `test/task_security_test.go` — Property 3: All Fargate task definitions enforce read-only filesystem and non-root execution. Use `rapid` to generate `app_name`, `runtime`; Linux: assert `readonlyRootFilesystem = true` and `user != "0"`; Windows: assert `readonlyRootFilesystem` absent. Tag: `// Feature: odot-aws-web-hosting, Property 3`. Test should FAIL. _Validates: Req 4.8, 9.8_
  - [x] 7.5 **RED**: Write unit test for Windows runtime. Assert `runtime = "windows"` → `WINDOWS_SERVER_2019_CORE` + `X86_64`. Assert `runtime = "linux"` → `LINUX`. Test should FAIL. _Req: 4.7_
  - [x] 7.6 **GREEN**: Write `modules/app-service/task-definition.tf`. Create task def with FARGATE, awsvpc. Linux: `readonlyRootFilesystem = true`, `user = "1000"`. Windows: `WINDOWS_SERVER_2019_CORE`, omit filesystem/user. Configure awslogs to `/ecs/{app_name}/{stage}`. Tests from 7.4/7.5 should PASS. _Req: 4.7, 4.8, 9.8_
  - [x] 7.7 **RED**: Write property test `test/waf_association_test.go` — Property 2: External-account ALBs always include WAF association. Use `rapid` with `account_type = "external"`; assert `aws_wafv2_web_acl_association` references the ALB. Tag: `// Feature: odot-aws-web-hosting, Property 2`. Test should FAIL. _Validates: Req 3.3, 3.5_
  - [x] 7.8 **GREEN**: Write `modules/app-service/alb.tf`. Create ALB (internal/internet-facing based on account_type), target group, listener. External: create WAF association + `waf-managed = true` tag. Test from 7.7 should PASS. _Req: 3.3, 3.4, 3.5_
  - [x] 7.9 **RED**: Write property test `test/autoscaling_test.go` — Property 8: Auto-scaling bounds always min=2, max=50. Use `rapid` to generate `app_name`, `stage`; assert `min_capacity = 2`, `max_capacity = 50`. Tag: `// Feature: odot-aws-web-hosting, Property 8`. Test should FAIL. _Validates: Req 4.4_
  - [x] 7.10 **GREEN**: Write `modules/app-service/autoscaling.tf`. Create `aws_appautoscaling_target` min=2, max=50. Scale-out: CPU/memory > 70% for 3min. Scale-in: CPU+memory < 30% for 10min. Test from 7.9 should PASS. _Req: 4.4, 4.5, 4.6_
  - [x] 7.11 **RED**: Write property test `test/log_retention_test.go` — Property 10: CloudWatch log retention matches stage. Assert `retention_in_days = 365` for prod, `90` otherwise. Tag: `// Feature: odot-aws-web-hosting, Property 10`. Test should FAIL. _Validates: Req 10.6_
  - [x] 7.12 **RED**: Write property test `test/alarms_test.go` — Property 11: Per-service alarms with correct thresholds. Assert exactly four alarms: CPU > 80% (300s), memory > 80% (300s), 5xx > 1% (300s), task count < 2. Tag: `// Feature: odot-aws-web-hosting, Property 11`. Test should FAIL. _Validates: Req 10.3_
  - [x] 7.13 **GREEN**: Write `modules/app-service/cloudwatch.tf`. Create log group with stage-based retention. Create four alarms wired to SNS. Tests from 7.11/7.12 should PASS. _Req: 10.3, 10.6_
  - [x] 7.14 **RED**: Write unit test for ECS service multi-AZ and circuit breaker. Assert `network_configuration.subnets` spans ≥ 2 AZs. Assert `deployment_circuit_breaker { enable = true, rollback = true }`. Test should FAIL. _Req: 4.3_
  - [x] 7.15 **GREEN**: Write `modules/app-service/ecs-service.tf`. Create `aws_ecs_service` with FARGATE, `network_configuration { subnets = var.private_subnet_ids }`, `deployment_circuit_breaker { enable = true, rollback = true }`, `desired_count = 2`. Test from 7.14 should PASS. _Req: 4.2, 4.3_
  - [x] 7.16 **RED**: Write property test `test/module_tagging_test.go` — Property 1: All resources carry required tags. Use `rapid` to generate inputs; assert every resource has non-empty `Environment`, `Project`, `Owner` tags. Tag: `// Feature: odot-aws-web-hosting, Property 1`. Test should FAIL. _Validates: Req 1.6, 11.5_
  - [x] 7.17 **GREEN**: Wire `modules/app-service/main.tf`, `variables.tf`, `outputs.tf`. Declare all variables, ensure all resources receive tags. Output `ecr_repository_url`, `alb_dns_name`, `ecs_service_name`, `task_definition_arn`. Test from 7.16 should PASS. _Req: 1.6, 4.1, 5.1, 7.3, 11.5_
  - [x] 7.18 **REFACTOR**: Add inline comments across all app-service files — Windows filesystem omission, circuit breaker behavior, ECR lifecycle logic, auto-scaling thresholds. _Req: 12.5_

---

## Phase 3 Checkpoint

- [x] Run `go test ./...` — all tests from Tasks 1–7 must pass
- [x] Resolve any failures before proceeding to Phase 4
