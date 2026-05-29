# Phase 1: Foundation — Repo Structure, OIDC, Networking

## Verification Gate
Run `go test ./...` — all tests from Tasks 1–3 must pass before proceeding to Phase 2.

## Dependencies
None — this is the starting phase.

---

## Tasks

- [x] 1. Initialize repository structure and Terraform backend bootstrap
  - [x] 1.1 **RED**: Write `test/state_key_test.go` — Property 9: Terraform state keys are unique per account-stage combination. Write test that reads `key` values from all six stack backend configs and asserts all six are distinct, each matching `{account}-{stage}/terraform.tfstate`. Tag: `// Feature: odot-aws-web-hosting, Property 9`. Test should FAIL because no backend configs exist yet. _Validates: Req 8.5_
  - [x] 1.2 **GREEN**: Create repository directory layout (`modules/`, `stacks/`, `docs/`, `scripts/`, `test/`). Write `backend.tf` and `versions.tf` (providers: `hashicorp/aws ~> 5.0`, `hashicorp/random`). Write `scripts/bootstrap-backend.sh` creating S3 state bucket with versioning+SSE-KMS and DynamoDB table `odot-terraform-locks`. Write six stack backend configs each with unique `key = "{account}-{stage}/terraform.tfstate"`. Test from 1.1 should now PASS. _Req: 8.2, 8.5_
  - [x] 1.3 **REFACTOR**: Add inline comments explaining backend configuration choices — S3 versioning purpose, DynamoDB locking rationale, state isolation strategy. _Req: 12.5_

- [x] 2. Implement `modules/oidc` — GitHub OIDC provider and IAM roles
  - [x] 2.1 **RED**: Write unit test for OIDC trust policy scoping. Assert trust policy condition uses specific repository name (not wildcard `*`). Assert `iam:PassRole` is scoped to ECS task execution roles only. Test should FAIL. _Req: 6.7, 9.6_
  - [x] 2.2 **GREEN**: Write `modules/oidc/main.tf`, `variables.tf`, `outputs.tf`. Create `aws_iam_openid_connect_provider` with GitHub thumbprint and audience `sts.amazonaws.com`. Create `aws_iam_role` with `sts:AssumeRoleWithWebIdentity` trust policy scoped to `repo:{github_org}/{repo}:*`. Attach least-privilege policy: `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, `ecs:RegisterTaskDefinition`, `ecs:UpdateService`, `ecs:DescribeServices`, `iam:PassRole` (scoped). Output `github_actions_role_arn`. Test from 2.1 should PASS. _Req: 6.7, 9.6, 13.1_
  - [x] 2.3 **REFACTOR**: Add inline comments on trust policy scoping rationale and PassRole limitation. _Req: 12.5_

- [x] 3. Implement `modules/networking` — VPC, subnets, routing, Client VPN
  - [x] 3.1 **RED**: Write property test `test/internal_vpc_test.go` — Property 12: Internal-account VPC configurations contain no internet gateway. Use `rapid` to generate random `vpc_cidr` and `availability_zones`; run `terraform plan`; assert no `aws_internet_gateway` and no subnet with `map_public_ip_on_launch = true`. Tag: `// Feature: odot-aws-web-hosting, Property 12`. Test should FAIL. _Validates: Req 2.3_
  - [x] 3.2 **RED**: Write unit tests for networking module. Assert `account_type = "internal"` → 0 public subnets, 0 IGW. Assert `account_type = "external"` → ≥ 2 public subnets, exactly 1 IGW. Tests should FAIL. _Req: 2.3, 3.1, 3.2_
  - [x] 3.3 **GREEN**: Write `modules/networking/main.tf`, `variables.tf`, `outputs.tf`. Accept inputs: `account_type`, `stage`, `vpc_cidr`, `availability_zones` (min 2), `tags`. Internal: VPC + private subnets only, no IGW, no public subnets, no `0.0.0.0/0` route. External: VPC + public subnets (IGW) + private subnets (NAT). Output `vpc_id`, `private_subnet_ids`, `public_subnet_ids`, `vpc_cidr_block`. Tests from 3.1/3.2 should PASS. _Req: 2.1, 2.3, 2.4, 3.1, 3.2_
  - [x] 3.4 **GREEN**: Provision Client VPN endpoint in internal VPCs. Create `aws_ec2_client_vpn_endpoint`, `aws_ec2_client_vpn_network_association`, `aws_ec2_client_vpn_authorization_rule` when `account_type = "internal"`. Document Direct Connect as a prerequisite (outside Terraform scope). _Req: 2.2_
  - [x] 3.5 **REFACTOR**: Add inline comments — why internal VPCs have no IGW, NAT placement for external, Client VPN config, Direct Connect prerequisite. _Req: 12.5_

---

## Phase 1 Checkpoint

- [x] Run `go test ./...` — all tests from Tasks 1–3 must pass
- [x] Resolve any failures before proceeding to Phase 2
