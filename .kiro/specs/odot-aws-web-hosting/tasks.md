# Implementation Plan: ODOT AWS Web Hosting POC

## Overview

This plan converts the ODOT AWS Web Hosting design into incremental coding tasks. All infrastructure is Terraform (HCL), all property-based and unit tests are Go (Terratest + rapid), and all CI/CD automation is GitHub Actions YAML. Tasks are ordered to build foundational modules first, then stacks, then the app template, then tests and monitoring — matching the 4-week roadmap.

---

## Tasks

- [x] 1. Initialize repository structure and Terraform backend bootstrap
  - Create the `odot-aws-platform` repository directory layout: `modules/`, `stacks/`, `docs/`, `scripts/`, `test/`
  - Write `backend.tf` and `versions.tf` (required providers: `hashicorp/aws ~> 5.0`, `hashicorp/random`) at the root
  - Write `scripts/bootstrap-backend.sh` that creates the S3 state bucket (`odot-terraform-state-{mgmt-account-id}`) with versioning and SSE-KMS, and the DynamoDB table `odot-terraform-locks` with `LockID` partition key
  - Write `stacks/internal-dev/backend.tf`, `stacks/internal-test/backend.tf`, `stacks/internal-prod/backend.tf`, `stacks/external-dev/backend.tf`, `stacks/external-test/backend.tf`, `stacks/external-prod/backend.tf` — each with a unique `key = "{account}-{stage}/terraform.tfstate"` pointing to the shared S3 bucket
  - _Requirements: 8.2, 8.5_

- [ ] 2. Implement `modules/oidc` — GitHub OIDC provider and IAM roles
  - [x] 2.1 Write `modules/oidc/main.tf`, `variables.tf`, `outputs.tf`
    - Create `aws_iam_openid_connect_provider` with GitHub thumbprint and audience `sts.amazonaws.com`
    - Create `aws_iam_role` with `sts:AssumeRoleWithWebIdentity` trust policy scoped to `token.actions.githubusercontent.com:sub` matching `repo:{github_org}/{repo}:*`
    - Attach least-privilege inline policy: `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, `ecs:RegisterTaskDefinition`, `ecs:UpdateService`, `ecs:DescribeServices`, `iam:PassRole` (scoped to ECS task execution roles)
    - Output `github_actions_role_arn`
    - _Requirements: 6.7, 9.6, 13.1_

  - [ ]* 2.2 Write unit test for OIDC trust policy scoping
    - Assert that the rendered trust policy condition uses the specific repository name, not a wildcard (`*`)
    - Assert that `iam:PassRole` is scoped to ECS task execution roles only, not `*`
    - _Requirements: 6.7, 9.6_

- [ ] 3. Implement `modules/networking` — VPC, subnets, routing
  - [ ] 3.1 Write `modules/networking/main.tf`, `variables.tf`, `outputs.tf`
    - Accept inputs: `account_type`, `stage`, `vpc_cidr`, `availability_zones` (min 2), `tags`
    - Internal path: create VPC + private subnets only; no `aws_internet_gateway`, no `aws_subnet` with `map_public_ip_on_launch = true`, no `0.0.0.0/0` route
    - External path: create VPC + public subnets (IGW-attached) + private subnets (NAT gateway for egress)
    - Output `vpc_id`, `private_subnet_ids`, `public_subnet_ids`, `vpc_cidr_block`
    - _Requirements: 2.1, 2.3, 2.4, 3.1, 3.2_

  - [ ]* 3.2 Write property test for internal VPC — Property 12
    - **Property 12: Internal-account VPC configurations contain no internet gateway**
    - **Validates: Requirements 2.3**
    - Use `rapid` to generate random `vpc_cidr` and `availability_zones` values; run `terraform plan -out=plan.json`; assert plan contains no `aws_internet_gateway` resource and no subnet with `map_public_ip_on_launch = true`
    - Tag: `// Feature: odot-aws-web-hosting, Property 12: Internal VPC has no IGW`

  - [ ]* 3.3 Write unit tests for networking module
    - Assert `account_type = "internal"` → 0 public subnets, 0 IGW resources
    - Assert `account_type = "external"` → ≥ 2 public subnets, exactly 1 IGW
    - _Requirements: 2.3, 3.1, 3.2_

- [ ] 4. Implement `modules/security` — GuardDuty, Security Hub, Config, Macie, KMS, SCPs
  - [ ] 4.1 Write `modules/security/main.tf`, `variables.tf`, `outputs.tf`
    - Create `aws_kms_key` with `enable_key_rotation = true` and alias `alias/odot-{account_type}`
    - Enable `aws_guardduty_detector` and create publishing destination to Security Hub
    - Enable `aws_securityhub_account` with FSBP standard (`aws_securityhub_standards_subscription`)
    - Enable `aws_config_configuration_recorder` with delivery channel to S3; create managed rules: `vpc-default-security-group-closed`, `iam-no-inline-policy`, `ecs-task-definition-nonroot-user`, `ecs-task-definition-memory-hard-limit`
    - Enable `aws_macie2_account` with classification job scanning all S3 buckets
    - Write SCP JSON files: `policies/scp-internal-no-igw.json` (deny `ec2:CreateInternetGateway`, `ec2:AttachInternetGateway`) and `policies/scp-external-waf-required.json` (deny internet-facing ALB without `waf-managed = true` tag)
    - Output `kms_key_arn`, `kms_key_id`, `guardduty_detector_id`
    - _Requirements: 1.2, 1.3, 9.1, 9.2, 9.3, 9.4, 9.5_

  - [ ]* 4.2 Write property test for KMS key rotation — Property 15
    - **Property 15: All KMS keys have annual key rotation enabled**
    - **Validates: Requirements 9.5**
    - Use `rapid` to generate `account_type` values; run `terraform plan`; assert `aws_kms_key` has `enable_key_rotation = true`
    - Tag: `// Feature: odot-aws-web-hosting, Property 15: All KMS keys have annual key rotation enabled`

- [ ] 5. Implement `modules/ecs-cluster` — ECS cluster with Fargate capacity providers
  - [ ] 5.1 Write `modules/ecs-cluster/main.tf`, `variables.tf`, `outputs.tf`
    - Create `aws_ecs_cluster` with `setting { name = "containerInsights", value = "enabled" }`
    - Create `aws_ecs_cluster_capacity_providers` registering both `FARGATE` and `FARGATE_SPOT`
    - Dev/Test default strategy: `FARGATE_SPOT` weight=1 base=1, `FARGATE` weight=0
    - Prod default strategy: `FARGATE` weight=1, `FARGATE_SPOT` weight=0
    - Output `cluster_arn`, `cluster_name`
    - _Requirements: 4.1, 4.2, 11.3_

  - [ ]* 5.2 Write property test for Container Insights — Property 14
    - **Property 14: ECS clusters always have Container Insights enabled**
    - **Validates: Requirements 10.1**
    - Use `rapid` to generate `cluster_name` and `stage` values; assert rendered `aws_ecs_cluster` has `setting` block with `name = "containerInsights"` and `value = "enabled"`
    - Tag: `// Feature: odot-aws-web-hosting, Property 14: ECS clusters always have Container Insights enabled`

  - [ ]* 5.3 Write property test for Fargate Spot on dev/test — Property 13
    - **Property 13: Dev and Test ECS services use Fargate Spot capacity provider**
    - **Validates: Requirements 11.3**
    - Use `rapid` to generate `app_name` with `stage` fixed to `"dev"` and `"test"`; assert `capacity_provider_strategy` block contains `FARGATE_SPOT` with `weight > 0`
    - Tag: `// Feature: odot-aws-web-hosting, Property 13: Dev and Test ECS services use Fargate Spot capacity provider`

- [ ] 6. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 7. Implement `modules/app-service` — ECR, ECS service, ALB, auto-scaling, alarms
  - [ ] 7.1 Write `modules/app-service/ecr.tf` — ECR repository and lifecycle policy
    - Create `aws_ecr_repository` with `image_scanning_configuration { scan_on_push = true }` and `encryption_configuration { encryption_type = "KMS", kms_key = var.kms_key_arn }`
    - Create `aws_ecr_lifecycle_policy` with exactly two rules: rule 1 — tagged images `countType = "imageCountMoreThan"`, `countNumber = 10`; rule 2 — untagged images `countType = "sinceImagePushed"`, `countNumber = 7`
    - _Requirements: 5.1, 5.2, 5.3, 5.5_

  - [ ]* 7.2 Write property test for ECR scan-on-push and KMS — Property 4
    - **Property 4: All ECR repositories have scan-on-push enabled and KMS encryption configured**
    - **Validates: Requirements 5.2, 5.3**
    - Use `rapid` to generate `app_name` and `account_type`; assert `image_scanning_configuration.scan_on_push = true` and `encryption_configuration.encryption_type = "KMS"` with non-null `kms_key`
    - Tag: `// Feature: odot-aws-web-hosting, Property 4: All ECR repositories have scan-on-push enabled and KMS encryption configured`

  - [ ]* 7.3 Write property test for ECR lifecycle policy — Property 5
    - **Property 5: ECR lifecycle policies enforce the correct retention rules**
    - **Validates: Requirements 5.5**
    - Use `rapid` to generate `app_name`; parse rendered lifecycle policy JSON; assert exactly two rules with the specified `countType` and `countNumber` values
    - Tag: `// Feature: odot-aws-web-hosting, Property 5: ECR lifecycle policies enforce the correct retention rules`

  - [ ] 7.4 Write `modules/app-service/task-definition.tf` — ECS task definition
    - Create `aws_ecs_task_definition` with `requires_compatibilities = ["FARGATE"]`, `network_mode = "awsvpc"`
    - Linux runtime: `readonlyRootFilesystem = true`, `user = "1000"`, `operatingSystemFamily = "LINUX"`
    - Windows runtime: `operatingSystemFamily = "WINDOWS_SERVER_2019_CORE"`, `cpuArchitecture = "X86_64"`, omit `readonlyRootFilesystem` and `user` (platform limitation)
    - Configure `awslogs` log driver pointing to `/ecs/{app_name}/{stage}`
    - _Requirements: 4.7, 4.8, 9.8_

  - [ ]* 7.5 Write property test for task definition security — Property 3
    - **Property 3: All Fargate task definitions enforce read-only filesystem and non-root execution**
    - **Validates: Requirements 4.8, 9.8**
    - Use `rapid` to generate `app_name`, `runtime`, `cpu`, `memory`; for Linux tasks assert `readonlyRootFilesystem = true` and `user != "0"` and `user != ""`; for Windows tasks assert `readonlyRootFilesystem` is absent
    - Tag: `// Feature: odot-aws-web-hosting, Property 3: All Fargate task definitions enforce read-only filesystem and non-root execution`

  - [ ]* 7.6 Write unit test for Windows runtime task definition
    - Assert `runtime = "windows"` → `operatingSystemFamily = "WINDOWS_SERVER_2019_CORE"` and `cpuArchitecture = "X86_64"`
    - Assert `runtime = "linux"` → `operatingSystemFamily = "LINUX"`
    - _Requirements: 4.7_

  - [ ] 7.7 Write `modules/app-service/alb.tf` — ALB, target group, security groups, WAF association
    - Create `aws_lb` (internal scheme for internal account, internet-facing for external)
    - Create `aws_lb_target_group` and `aws_lb_listener`
    - External account only: create `aws_wafv2_web_acl_association` linking WAF ACL to ALB; add `aws:RequestTag/waf-managed = true` to ALB resource tags
    - _Requirements: 3.3, 3.4, 3.5_

  - [ ]* 7.8 Write property test for WAF association on external ALBs — Property 2
    - **Property 2: External-account ALB configurations always include a WAF association**
    - **Validates: Requirements 3.3, 3.5**
    - Use `rapid` to generate `app_name` with `account_type = "external"`; assert plan contains `aws_wafv2_web_acl_association` whose `resource_arn` references the ALB in the same config
    - Tag: `// Feature: odot-aws-web-hosting, Property 2: External-account ALB configurations always include a WAF association`

  - [ ] 7.9 Write `modules/app-service/autoscaling.tf` — ECS auto-scaling policies
    - Create `aws_appautoscaling_target` with `min_capacity = 2`, `max_capacity = 50`
    - Scale-out policy: CPU or memory > 70% for 3 minutes (180s)
    - Scale-in policy: CPU and memory < 30% for 10 minutes (600s)
    - _Requirements: 4.4, 4.5, 4.6_

  - [ ]* 7.10 Write property test for auto-scaling bounds — Property 8
    - **Property 8: ECS service auto-scaling bounds are always min=2, max=50**
    - **Validates: Requirements 4.4**
    - Use `rapid` to generate `app_name` and `stage`; assert `aws_appautoscaling_target` has `min_capacity = 2` and `max_capacity = 50`
    - Tag: `// Feature: odot-aws-web-hosting, Property 8: ECS service auto-scaling bounds are always min=2, max=50`

  - [ ] 7.11 Write `modules/app-service/cloudwatch.tf` — log group, CloudWatch alarms
    - Create `aws_cloudwatch_log_group` `/ecs/{app_name}/{stage}` with `retention_in_days = 365` for prod, `90` for dev/test
    - Create four `aws_cloudwatch_metric_alarm` resources: CPU > 80% (300s), memory > 80% (300s), ALB 5xx rate > 1% (300s), ECS task count < 2 (threshold = 2)
    - Wire each alarm to `var.sns_topic_arn`
    - _Requirements: 10.3, 10.6_

  - [ ]* 7.12 Write property test for log retention by stage — Property 10
    - **Property 10: CloudWatch log retention matches stage**
    - **Validates: Requirements 10.6**
    - Use `rapid` to generate `app_name` and `stage`; assert `retention_in_days = 365` when `stage = "prod"` and `retention_in_days = 90` otherwise
    - Tag: `// Feature: odot-aws-web-hosting, Property 10: CloudWatch log retention matches stage`

  - [ ]* 7.13 Write property test for CloudWatch alarm thresholds — Property 11
    - **Property 11: Per-service CloudWatch alarms are always provisioned with correct thresholds**
    - **Validates: Requirements 10.3**
    - Use `rapid` to generate `app_name` and `stage`; assert plan contains exactly four alarm resources with the specified thresholds (CPU > 80%, memory > 80%, 5xx > 1%, task count < 2)
    - Tag: `// Feature: odot-aws-web-hosting, Property 11: Per-service CloudWatch alarms are always provisioned with correct thresholds`

  - [ ] 7.14 Wire `modules/app-service/main.tf`, `variables.tf`, `outputs.tf`
    - Declare all input variables from the design (see Components section)
    - Output `ecr_repository_url`, `alb_dns_name`, `ecs_service_name`, `task_definition_arn`
    - _Requirements: 4.1, 5.1, 7.3_

- [ ] 8. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 9. Implement `modules/monitoring` — CloudWatch dashboards, SNS, Chatbot, Budgets
  - [ ] 9.1 Write `modules/monitoring/main.tf`, `variables.tf`, `outputs.tf`
    - Create `aws_sns_topic` named `odot-alerts-{account_type}` with KMS encryption
    - Create `aws_chatbot_slack_channel_configuration` pointing to the appropriate Slack channel
    - Create `aws_cloudwatch_dashboard` per stage per account (6 total) with widgets: ECS task count, CPU utilization, memory utilization, ALB request count, ALB 5xx error rate, active alarm count
    - Create `aws_budgets_budget` with `limit_amount = 1000`, `time_unit = MONTHLY`, notification at 80% (`FORECASTED`)
    - Create `aws_sns_topic_subscription` for email endpoint (ServiceNow/FortiSIEM)
    - Output `sns_topic_arn`, `dashboard_name`
    - _Requirements: 10.2, 10.4, 10.5, 11.1, 11.2_

  - [ ] 9.2 Write EventBridge rule for Security Hub Critical/High findings → SNS
    - Create `aws_cloudwatch_event_rule` matching `aws.securityhub` source with `detail.findings.Severity.Label` in `["CRITICAL", "HIGH"]`
    - Create `aws_cloudwatch_event_target` routing to the SNS topic
    - _Requirements: 9.9_

- [ ] 10. Implement stack configurations — wire modules into six deployable stacks
  - [ ] 10.1 Write `stacks/internal-dev/main.tf` and `terraform.tfvars`
    - Call `networking` module with `account_type = "internal"`, `stage = "dev"`
    - Call `ecs-cluster` module
    - Call `security` module
    - Call `monitoring` module
    - Call `oidc` module
    - _Requirements: 1.1, 8.3_

  - [ ] 10.2 Write `stacks/internal-test/main.tf` and `stacks/internal-prod/main.tf`
    - Mirror `internal-dev` with appropriate `stage` values
    - Prod: set `FARGATE` as primary capacity provider in cluster module
    - _Requirements: 1.1, 8.3_

  - [ ] 10.3 Write `stacks/external-dev/main.tf`, `stacks/external-test/main.tf`, `stacks/external-prod/main.tf`
    - Call `networking` module with `account_type = "external"`, appropriate `stage`
    - Call `ecs-cluster`, `security`, `monitoring`, `oidc` modules
    - Pass `waf_acl_arn` to `app-service` module calls
    - _Requirements: 1.1, 3.3, 8.3_

  - [ ] 10.4 Write `stacks/*/provider.tf` for all six stacks
    - Configure `aws` provider with `assume_role { role_arn = ... }` per account
    - Use provider aliases for multi-account Terraform pattern
    - _Requirements: 8.1_

- [ ] 11. Implement property and unit tests for cross-cutting concerns
  - [ ] 11.1 Write `test/module_tagging_test.go` — Property 1
    - **Property 1: All module-produced resources carry required tags**
    - **Validates: Requirements 1.6, 11.5**
    - Use `rapid` to generate `app_name`, `stage`, `account_type`, `runtime`; run `terraform plan`; iterate all planned resources; assert each has non-empty `Environment`, `Project`, and `Owner` tags
    - Tag: `// Feature: odot-aws-web-hosting, Property 1: All module-produced resources carry required tags`

  - [ ] 11.2 Write `test/state_key_test.go` — Property 9
    - **Property 9: Terraform state keys are unique per account-stage combination**
    - **Validates: Requirements 8.5**
    - For all six `(account, stage)` pairs, read the `key` value from each stack's `backend.tf`; assert all six keys are distinct strings each matching `{account}-{stage}/terraform.tfstate`
    - Tag: `// Feature: odot-aws-web-hosting, Property 9: Terraform state keys are unique per account-stage combination`

- [ ] 12. Implement scanner gate logic and image tagging utilities
  - [ ] 12.1 Write `scripts/scanner-gate.go` (or `scanner_gate.go` in `test/`)
    - Implement `EvaluateScanResult(doc ScanDocument) GateResult` that returns `FAIL` if any finding has severity `CRITICAL` or `HIGH`, otherwise `PASS`
    - Handle both Trivy JSON format and Inspector SBOM format
    - _Requirements: 6.3, 6.4_

  - [ ]* 12.2 Write property test for scanner gate severity logic — Property 6
    - **Property 6: Scanner gate correctly classifies vulnerability severity**
    - **Validates: Requirements 6.4**
    - Use `rapid` to generate scanner output documents with random combinations of severities; assert `FAIL` iff at least one `CRITICAL` or `HIGH` finding is present; assert `PASS` for documents with only `MEDIUM`, `LOW`, or `INFORMATIONAL`
    - Tag: `// Feature: odot-aws-web-hosting, Property 6: Scanner gate correctly classifies vulnerability severity`

  - [ ] 12.3 Write `scripts/image-tag.go` — image tag generation function
    - Implement `GenerateTags(commitSHA, branchName string) []string` returning `[commitSHA, branchName+"-latest"]`
    - _Requirements: 6.5_

  - [ ]* 12.4 Write property test for image tag encoding — Property 7
    - **Property 7: Image tags always encode both commit SHA and branch name**
    - **Validates: Requirements 6.5**
    - Use `rapid` to generate `(commit_sha, branch_name)` pairs; assert returned tag set contains `commit_sha` and `branch_name + "-latest"`
    - Tag: `// Feature: odot-aws-web-hosting, Property 7: Image tags always encode both commit SHA and branch name`

- [ ] 13. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 14. Implement `odot-app-template` repository
  - [ ] 14.1 Create `odot-app-template` repository structure
    - Create `.github/workflows/ci-cd.yml` — full build/scan/deploy pipeline (see design §7)
    - Create `.github/workflows/pr-checks.yml` — PR validation (lint, unit tests)
    - Create `terraform/main.tf` calling `app-service` module with variable references
    - Create `terraform/variables.tf` with `app_name`, `runtime`, `container_port`, `cpu`, `memory`
    - Create `terraform/terraform.tfvars.example` with inline comments on each variable
    - Create `Dockerfile` stub (multi-stage, non-root user, minimal base image)
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

  - [ ] 14.2 Write `ci-cd.yml` GitHub Actions workflow
    - Trigger: `on: push: branches: [dev, test, prod]`
    - Job `unit-test`: run application unit tests; halt pipeline on failure
    - Job `scan` (depends on `unit-test`): Trivy (`exit-code: '1'`, `severity: 'CRITICAL,HIGH'`), Inspector (`amazon-inspector-scan` action + post-processing step calling `scanner-gate`), CodeQL (`github/codeql-action/analyze`)
    - Job `build-push` (depends on `scan`): Docker build + ECR push tagged `{SHA}-{branch}` and `{branch}-latest`; use `GenerateTags` output
    - Job `deploy-dev` / `deploy-test` (depends on `build-push`, branch-conditional): ECS rolling deploy via `aws ecs update-service`
    - Job `deploy-prod` (depends on `build-push`, branch=prod): GitHub Environment manual approval gate, then ECS rolling deploy
    - OIDC auth in every AWS job: `permissions: id-token: write`, `aws-actions/configure-aws-credentials@v4` with `role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}`
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8_

  - [ ] 14.3 Write `CONTRIBUTING.md` and `README.md` for `odot-app-template`
    - Explain how to add new routes, update Dockerfile, trigger deployments, and set Terraform variables
    - _Requirements: 7.6, 12.4_

- [ ] 15. Write documentation for `odot-aws-platform`
  - [ ] 15.1 Write `README.md` for `odot-aws-platform`
    - Describe overall architecture, account structure, Terraform module layout
    - Include instructions for `terraform init`, `terraform plan`, `terraform apply`, `terraform destroy`
    - _Requirements: 12.1_

  - [ ] 15.2 Write `docs/runbook.md`
    - Document: onboarding a new application via App_Template, responding to common CloudWatch alarms, rotating KMS keys, adding a new Notification_Channel
    - _Requirements: 12.2_

  - [ ] 15.3 Write architecture diagrams in `docs/architecture/`
    - `network-topology.md` (or `.mmd`) — network topology for both accounts (Mermaid)
    - `cicd-pipeline.md` — CI/CD pipeline flow (Mermaid)
    - `ecs-cluster-layout.md` — ECS cluster layout per stage
    - _Requirements: 12.3_

- [ ] 16. Write smoke test script
  - Write `scripts/smoke-test.sh` that accepts `{account} {stage}` arguments and uses `aws` CLI to assert:
    - 6 ECS clusters exist across both accounts
    - GuardDuty detector is enabled in both accounts
    - Security Hub FSBP standard is active in both accounts
    - AWS Budgets alert is configured at $800 threshold
    - All 6 CloudWatch dashboards exist
    - GitHub Actions workflow YAML contains `role-to-assume` and no `AWS_ACCESS_KEY_ID` references
    - `odot-app-template` repository has `is_template = true`
  - _Requirements: 9.1, 9.2, 11.1, 10.2, 13.1, 13.2, 13.3, 13.4_

- [ ] 17. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

---

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP delivery
- Each task references specific requirements for traceability
- Checkpoints at tasks 6, 8, 13, and 17 ensure incremental validation
- Property tests (P1–P15) operate on `terraform plan` JSON output — no AWS credentials required
- Integration tests (not listed as tasks here) require a sandbox AWS account and are run separately via `go test ./integration/... -v -timeout 30m`
- Smoke tests (task 16) require deployed environment credentials
- Windows Fargate tasks cannot use `readonlyRootFilesystem` — Property 3 test must exempt Windows runtime (see design §Error Handling)
- Windows Fargate tasks fall back to `FARGATE` capacity provider regardless of stage — Property 13 test applies to Linux tasks only
- All Go test files must include the tag comment `// Feature: odot-aws-web-hosting, Property {N}: {property_text}` per the design testing strategy

---

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["2.1", "3.1"] },
    { "id": 1, "tasks": ["2.2", "3.2", "3.3", "4.1"] },
    { "id": 2, "tasks": ["4.2", "5.1"] },
    { "id": 3, "tasks": ["5.2", "5.3", "7.1"] },
    { "id": 4, "tasks": ["7.2", "7.3", "7.4"] },
    { "id": 5, "tasks": ["7.5", "7.6", "7.7"] },
    { "id": 6, "tasks": ["7.8", "7.9"] },
    { "id": 7, "tasks": ["7.10", "7.11"] },
    { "id": 8, "tasks": ["7.12", "7.13", "7.14"] },
    { "id": 9, "tasks": ["9.1", "9.2", "11.1", "11.2", "12.1", "12.3"] },
    { "id": 10, "tasks": ["10.1", "12.2", "12.4"] },
    { "id": 11, "tasks": ["10.2", "10.3"] },
    { "id": 12, "tasks": ["10.4", "14.1"] },
    { "id": 13, "tasks": ["14.2", "14.3", "15.1", "15.2", "15.3", "16"] }
  ]
}
```
