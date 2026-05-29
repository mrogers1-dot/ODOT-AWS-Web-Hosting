# Phase 9: Security Hardening — WAF Rules, NIST, Secrets, IaC Scanning, Tag Governance

## Verification Gate
Run `go test ./...` — all new property tests (P19, P20, P21, P22) pass. Platform CI pipeline (tfsec + OPA) passes on current code.

## Dependencies
Phase 8 must be complete (TLS and connectivity must work before hardening layers on top).

---

## Tasks

- [x] 27. Implement WAF managed rule groups and rate-based rule
  - [x] 27.1 **RED**: Write property test `test/waf_rules_test.go` — Property 19: Every external WAF ACL contains the 3 AWS managed rule groups (`CommonRuleSet`, `KnownBadInputsRuleSet`, `SQLiRuleSet`) + a rate-based rule (2000 req/5min), default action allow. Test should FAIL. _Validates: Req 18.1, 18.2, 18.3, 18.4, 18.6_
  - [x] 27.2 **GREEN**: Create `modules/app-service/waf.tf` (or update existing WAF config). Define `aws_wafv2_web_acl` with the 3 managed rule group statements, a rate-based rule (limit=2000, action=block), default action=allow, and `visibility_config` with CloudWatch metrics enabled. Enable WAF logging to CloudWatch Logs group `aws-waf-logs-odot-{stage}`. Update the WAF association to reference this ACL. Test from 27.1 should PASS. _Req: 18.1–18.6_
  - [x] 27.3 **REFACTOR**: Add inline comments explaining each rule group's purpose, rate-limit threshold rationale, and WAF logging configuration. _Req: 12.5_

- [x] 28. Enable NIST 800-53 in Security Hub and create compliance mapping
  - [x] 28.1 **RED**: Write property test `test/securityhub_nist_test.go` — Property 20: Security module subscribes to both FSBP and NIST 800-53 Rev 5 standards. Test should FAIL. _Validates: Req 19.1_
  - [x] 28.2 **GREEN**: Update `modules/security/main.tf`. Add second `aws_securityhub_standards_subscription` for `arn:aws:securityhub:{region}::standards/nist-800-53/v/5.0.0`. Test from 28.1 should PASS. _Req: 19.1_
  - [x] 28.3 **GREEN**: Write `docs/compliance/nist-800-53-mapping.md`. Map each implemented control to its NIST control family (AC, AU, SC, SI, CM, IA, etc.). Include a "Not Applicable for POC" table with rationale. _Req: 19.2, 19.3_
  - [x] 28.4 **REFACTOR**: Add inline comment in security module referencing the compliance mapping doc. _Req: 12.5_

- [x] 29. Move Okta client secret to Secrets Manager
  - [x] 29.1 **RED**: Write property test `test/okta_secret_test.go` — Property 21: The admin-dashboard module sources the Okta secret from a `data "aws_secretsmanager_secret_version"` lookup, not a plaintext variable default. Test should FAIL. _Validates: Req 20.1, 20.2_
  - [x] 29.2 **GREEN**: Update `modules/admin-dashboard/variables.tf` — replace `okta_client_secret` (sensitive string) with `okta_client_secret_arn` (string, ARN of the Secrets Manager secret). Update `modules/admin-dashboard/cognito.tf` — add `data "aws_secretsmanager_secret_version"` and reference `data.aws_secretsmanager_secret_version.okta.secret_string` in the identity provider config. Test from 29.1 should PASS. _Req: 20.1, 20.2, 20.4_
  - [x] 29.3 **GREEN**: Update IAM roles — grant Cognito and dashboard task roles `secretsmanager:GetSecretValue` scoped to the specific secret ARN. _Req: 20.3_
  - [x] 29.4 **REFACTOR**: Add inline comments on why the secret is in Secrets Manager, state encryption note, and rotation guidance. _Req: 12.5_

- [x] 30. Implement platform CI pipeline with tfsec and OPA/Conftest
  - [x] 30.1 **GREEN**: Create `.github/workflows/platform-ci.yml` in `odot-aws-platform`. On PR: checkout → setup Terraform → `terraform init` (all modules) → run tfsec (fail on HIGH/CRITICAL) → run `terraform plan -out` → `terraform show -json` → `conftest test` against `policy/*.rego`. _Req: 21.1, 21.2, 21.3, 21.4_
  - [x] 30.2 **GREEN**: Write `policy/tags.rego` — assert every planned resource has Environment/Project/Owner tags. _Req: 21.3_
  - [x] 30.3 **GREEN**: Write `policy/security_groups.rego` — assert no SG allows `0.0.0.0/0` ingress except external ALB SGs on port 443. _Req: 21.3_
  - [x] 30.4 **GREEN**: Write `policy/encryption.rego` — assert all S3/DynamoDB/ECR/logs resources have encryption configured. _Req: 21.3_
  - [x] 30.5 **GREEN**: Write `scripts/policy-check.sh` wrapping the plan → show → conftest flow for local developer use. _Req: 21.3_
  - [x] 30.6 **REFACTOR**: Add README section on running policy checks locally and CI behavior. _Req: 12.5_

- [x] 31. Implement AWS Organizations Tag Policy
  - [x] 31.1 **RED**: Write property test `test/tag_policy_test.go` — Property 22: A management-account config defines a TAG_POLICY requiring Environment (∈ dev/test/prod), Project, and Owner tags. Test should FAIL. _Validates: Req 22.1, 22.2, 22.3_
  - [x] 31.2 **GREEN**: Create `stacks/management/tag-policy.tf`. Define `aws_organizations_policy` (type TAG_POLICY) with the three required tags and `Environment` constrained to `dev|test|prod`. Attach to the ODOT-Web OU via `aws_organizations_policy_attachment`. Test from 31.1 should PASS. _Req: 22.1, 22.2, 22.3_
  - [x] 31.3 **REFACTOR**: Add inline comments explaining tag policy enforcement behavior and how it complements module-level tagging. _Req: 12.5_

---

## Phase 9 Checkpoint

- [x] Run `go test ./...` — all tests from Phases 1–9 pass
- [x] Platform CI workflow (tfsec + OPA) passes on current codebase
- [x] Compliance mapping document is complete
- [x] Resolve any failures before proceeding to Phase 10
