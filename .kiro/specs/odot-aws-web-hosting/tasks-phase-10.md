# Phase 10: Resilience & Observability — FIS, Scaling Model, Canaries, Tracing

## Verification Gate
Run `go test ./...` — all new property tests (P23) pass. FIS experiment templates validate. Canary and tracing configs are syntactically valid.

## Dependencies
Phase 9 must be complete (security hardening in place before resilience testing).

---

## Tasks

- [x] 32. Implement AWS Fault Injection Simulator experiments
  - [x] 32.1 **GREEN**: Create `modules/resilience/main.tf`, `variables.tf`, `outputs.tf`. Define FIS experiment template `fis-stop-tasks-single-az` — action `aws:ecs:stop-task` targeting 50% of tasks in one AZ. Define stop condition wired to a CloudWatch alarm (halt if running tasks < 1). _Req: 23.1, 23.2_
  - [x] 32.2 **GREEN**: Define FIS experiment template `fis-bad-deployment` — registers a task definition with a non-existent image, updates the service, and asserts the circuit breaker rolls back within 5 minutes. _Req: 23.3_
  - [x] 32.3 **GREEN**: Create IAM role for FIS with permissions to stop ECS tasks and update services. _Req: 23.1_
  - [x] 32.4 **GREEN**: Update `docs/runbook.md` — add "Resilience Testing" section documenting each experiment, expected recovery behavior, and how to run them. _Req: 23.4_
  - [x] 32.5 **REFACTOR**: Add inline comments on stop conditions, why 50% task selection, and circuit breaker interaction. _Req: 12.5_

- [x] 33. Document and implement the shared-ALB scaling model
  - [x] 33.1 **GREEN**: Update `modules/app-service/variables.tf` — add optional `shared_alb_listener_arn` variable (string, default empty). When set, the module creates a listener rule + target group instead of a dedicated ALB. _Req: 24.1_
  - [x] 33.2 **GREEN**: Update `modules/app-service/alb.tf` — add conditional logic: if `shared_alb_listener_arn != ""`, create `aws_lb_listener_rule` with host-header condition matching `{app_name}.{domain}` and forward to the target group. Skip ALB, listener, and WAF association creation. _Req: 24.1_
  - [x] 33.3 **GREEN**: Update README capacity-planning section — document the shared-ALB model, quota limits (100 rules/ALB, 100 TGs/ALB), sharding strategy at scale, and when to request quota increases. _Req: 24.2, 24.3_
  - [x] 33.4 **REFACTOR**: Add inline comments explaining the shared vs dedicated ALB decision and the host-routing pattern. _Req: 12.5_

- [x] 34. Implement CloudWatch Synthetics canaries and SLO tracking
  - [x] 34.1 **RED**: Write property test `test/canary_test.go` — Property 23: The monitoring module provisions a Synthetics canary with an associated failure alarm routed to SNS. Test should FAIL. _Validates: Req 25.1, 25.2_
  - [x] 34.2 **GREEN**: Update `modules/monitoring/main.tf` (or create `canary.tf`). Add `aws_synthetics_canary` resource (heartbeat blueprint, 5-min schedule, S3 artifact bucket). Add `aws_cloudwatch_metric_alarm` on `SuccessPercent < 100` → SNS. Add new variables: `canary_endpoints` (list of URLs to monitor). Test from 34.1 should PASS. _Req: 25.1, 25.2_
  - [x] 34.3 **GREEN**: Add SLO metric math expression to the monitoring module — `(successful_requests / total_requests) * 100` over 30 days. Add output `slo_attainment_metric_name` for dashboard consumption. _Req: 25.3_
  - [x] 34.4 **GREEN**: Update the admin-dashboard detail page design to include SLO attainment percentage and error budget remaining. _Req: 25.4_
  - [x] 34.5 **REFACTOR**: Add inline comments on canary blueprint choice, SLO calculation methodology, and error budget concept. _Req: 12.5_

- [x] 35. Implement distributed tracing with ADOT sidecar
  - [x] 35.1 **GREEN**: Update `modules/app-service/task-definition.tf`. Add optional ADOT sidecar container definition when `var.enable_tracing = true`. Configure the sidecar with X-Ray exporter. Add new variable `enable_tracing` (bool, default false). _Req: 26.1, 26.2_
  - [x] 35.2 **GREEN**: Update `modules/app-service/iam.tf` (or task-definition.tf). Add `xray:PutTraceSegments` and `xray:PutTelemetryRecords` to the task execution role when tracing is enabled. _Req: 26.3_
  - [x] 35.3 **GREEN**: Update `odot-app-template/CONTRIBUTING.md` — add "Enabling Distributed Tracing" section documenting OTEL env vars, SDK setup per runtime (Node.js, Python, .NET), and how to view traces in X-Ray. _Req: 26.4_
  - [x] 35.4 **REFACTOR**: Add inline comments on ADOT collector config, X-Ray sampling rules, and sidecar resource allocation. _Req: 12.5_

---

## Phase 10 Checkpoint

- [x] Run `go test ./...` — all tests from Phases 1–10 pass
- [x] FIS experiment templates are syntactically valid
- [x] Shared-ALB conditional logic compiles without errors
- [x] Canary and tracing configurations validate
- [x] Resolve any failures before proceeding to Phase 11
