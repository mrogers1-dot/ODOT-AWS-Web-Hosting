# Phase 8: Connectivity & TLS — VPC Endpoints, HTTPS, ALB Access Logs

## Verification Gate
Run `go test ./...` — all new property tests (P16, P17, P18) pass alongside existing tests. `terraform validate` succeeds on all stacks.

## Dependencies
Phases 1–7 must be complete. This phase fixes the "it won't actually work" tier.

---

## Tasks

- [x] 24. Implement VPC interface endpoints and S3 gateway endpoint for Internal VPCs
  - [x] 24.1 **RED**: Write property test `test/vpc_endpoints_test.go` — Property 16: Internal VPCs contain all 7 required interface endpoints (`ecr.api`, `ecr.dkr`, `logs`, `secretsmanager`, `ssm`, `ssmmessages`, `sts`) + 1 S3 gateway endpoint; external VPCs contain none. Test should FAIL. _Validates: Req 15.1, 15.2, 15.3_
  - [x] 24.2 **GREEN**: Update `modules/networking/main.tf`. Add `aws_vpc_endpoint` (interface) for each of the 7 services when `account_type = "internal"`. Add `aws_vpc_endpoint` (gateway) for S3 associated with all private route tables. Create a dedicated security group allowing inbound 443 from VPC CIDR. Set `private_dns_enabled = true` on all interface endpoints. Test from 24.1 should PASS. _Req: 15.1, 15.2, 15.4, 15.5, 15.7_
  - [x] 24.3 **GREEN**: Add new variable `region` (default `"us-east-2"`) to the networking module for constructing endpoint service names. Add output `vpc_endpoint_ids` (map of service name → endpoint ID). _Req: 15.1_
  - [x] 24.4 **REFACTOR**: Add inline comments explaining why each endpoint is needed (ECR pull path, log delivery, secrets retrieval), the zero-egress rationale, and the S3 gateway vs interface distinction. _Req: 12.5_

- [x] 25. Implement TLS termination with ACM, HTTPS listener, and Route 53
  - [x] 25.1 **RED**: Write property test `test/tls_listener_test.go` — Property 17: Every ALB has an HTTPS:443 listener with a TLS1.2+ policy and an HTTP:80 listener that redirects 301 to HTTPS. Test should FAIL. _Validates: Req 16.2, 16.3_
  - [x] 25.2 **GREEN**: Update `modules/app-service/alb.tf`. Add new variables: `domain_name`, `hosted_zone_id`, `certificate_arn` (optional — if empty, create ACM cert with DNS validation). Create `aws_acm_certificate` + `aws_route53_record` for DNS validation + `aws_acm_certificate_validation`. Create HTTPS:443 listener with the cert and `ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"`. Replace the HTTP:80 forward action with a redirect action (301 → HTTPS). Create Route 53 A-record alias pointing domain to ALB. Test from 25.1 should PASS. _Req: 16.1, 16.2, 16.3, 16.4, 16.5_
  - [x] 25.3 **GREEN**: Update `modules/app-service/variables.tf` with new variables (`domain_name`, `hosted_zone_id`, `certificate_arn`). Update `modules/app-service/outputs.tf` with `certificate_arn` and `app_url` outputs. _Req: 16.1_
  - [x] 25.4 **REFACTOR**: Add inline comments on TLS policy choice, why HTTP redirects rather than drops, and ACM DNS validation flow. Update the app-template CONTRIBUTING.md with DNS/TLS setup instructions. _Req: 12.5, 16.6_

- [x] 26. Implement ALB access logging to S3
  - [x] 26.1 **RED**: Write property test `test/alb_access_logs_test.go` — Property 18: Every ALB has `access_logs { enabled = true }` pointing to an encrypted, public-access-blocked S3 bucket. Test should FAIL. _Validates: Req 17.1, 17.2_
  - [x] 26.2 **GREEN**: Update `modules/app-service/alb.tf`. Create `aws_s3_bucket` for ALB access logs with SSE-S3 encryption, `aws_s3_bucket_public_access_block`, lifecycle policy (IA at 30 days, expire at 365 days), and bucket policy granting the ELB service account + `delivery.logs.amazonaws.com` write access. Enable `access_logs` block on the ALB resource. Test from 26.1 should PASS. _Req: 17.1, 17.2, 17.3, 17.4_
  - [x] 26.3 **REFACTOR**: Add inline comments on the ELB account ID lookup pattern, lifecycle rationale, and how the dashboard consumes these logs. _Req: 12.5_

---

## Phase 8 Checkpoint

- [x] Run `go test ./...` — all tests from Phases 1–8 pass
- [x] `terraform validate` succeeds on all six stacks
- [x] Resolve any failures before proceeding to Phase 9
