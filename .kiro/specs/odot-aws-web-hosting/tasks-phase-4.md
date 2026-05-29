# Phase 4: Monitoring & Utilities — CloudWatch, Budgets, Scanner Gate, Versioning

## Verification Gate
Run `go test ./...` — all tests from Tasks 1–12 must pass before proceeding to Phase 5.

## Dependencies
Phase 3 must be complete and passing (app-service module needed for monitoring integration).

---

## Tasks

- [x] 9. Implement `modules/monitoring` — CloudWatch dashboards, SNS, Chatbot, Budgets, EventBridge
  - [x] 9.1 **RED**: Write unit test for monitoring module. Assert SNS topic name follows `odot-alerts-{account_type}`. Assert budget threshold at 80%. Assert EventBridge rule for ECS task exits exists. Assert EventBridge rule for Security Hub Critical/High findings exists. Test should FAIL. _Req: 9.9, 10.4, 10.7, 11.2_
  - [x] 9.2 **GREEN**: Write `modules/monitoring/main.tf`, `variables.tf`, `outputs.tf`. Create SNS topic `odot-alerts-{account_type}` with KMS. Create Chatbot Slack config. Create CloudWatch dashboards (ECS tasks, CPU, memory, ALB requests, 5xx, alarms). Create budget $1000/month with 80% notification. Create SNS email subscription. Create EventBridge rule for ECS task `STOPPED` (unexpected) → SNS. Create EventBridge rule for Security Hub Critical/High → SNS. Output `sns_topic_arn`, `dashboard_name`. Test from 9.1 should PASS. _Req: 9.9, 10.2, 10.4, 10.5, 10.7, 11.1, 11.2_
  - [x] 9.3 **REFACTOR**: Add inline comments — EventBridge filter for unexpected exits vs scaling, Security Hub notification path, budget threshold choice, Chatbot fallback. _Req: 12.5_

- [x] 10. Configure module versioning strategy
  - [x] 10.1 **RED**: Write test asserting module source references use Git tags. Parse all `stacks/*/main.tf`; assert every `module` block's `source` uses `?ref=v` syntax. Test should FAIL. _Req: 8.6_
  - [x] 10.2 **GREEN**: Update all stack `main.tf` to reference modules via `source = "git::https://github.com/{org}/odot-aws-platform.git//modules/{name}?ref=v1.0.0"`. Create `MODULES_CHANGELOG.md` documenting v1.0.0. Tag repository `v1.0.0`. Test from 10.1 should PASS. _Req: 8.6_
  - [x] 10.3 **REFACTOR**: Add "Module Versioning" section to README explaining version bump workflow and changelog convention. _Req: 8.6, 12.1_

- [x] 12. Implement scanner gate logic and image tagging utilities
  - [x] 12.1 **RED**: Write property test `test/scanner_gate_test.go` — Property 6: Scanner gate correctly classifies severity. Use `rapid` to generate scanner outputs; assert FAIL iff Critical/High present; assert PASS for Medium/Low/Informational only. Tag: `// Feature: odot-aws-web-hosting, Property 6`. Test should FAIL. _Validates: Req 6.4_
  - [x] 12.2 **RED**: Write property test `test/image_tag_test.go` — Property 7: Image tags encode both commit SHA and branch name. Use `rapid` to generate `(sha, branch)` pairs; assert tags contain `sha` and `branch + "-latest"`. Tag: `// Feature: odot-aws-web-hosting, Property 7`. Test should FAIL. _Validates: Req 6.5_
  - [x] 12.3 **GREEN**: Write `scripts/scanner-gate.go`. Implement `EvaluateScanResult` returning FAIL for Critical/High, PASS otherwise. Handle Trivy JSON and Inspector SBOM formats. Test from 12.1 should PASS. _Req: 6.3, 6.4_
  - [x] 12.4 **GREEN**: Write `scripts/image-tag.go`. Implement `GenerateTags(commitSHA, branchName) []string` returning `[commitSHA, branchName+"-latest"]`. Test from 12.2 should PASS. _Req: 6.5_
  - [x] 12.5 **REFACTOR**: Add error handling for empty/malformed input, comments on format differences. _Req: 12.5_

---

## Phase 4 Checkpoint

- [x] Run `go test ./...` — all tests from Tasks 1–12 must pass
- [x] Resolve any failures before proceeding to Phase 5
