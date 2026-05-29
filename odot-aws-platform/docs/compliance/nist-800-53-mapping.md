# NIST 800-53 Rev 5 Control Mapping

This document maps the ODOT AWS Web Hosting platform's security controls to their corresponding NIST 800-53 Rev 5 control families. It demonstrates compliance alignment for state-government audit review.

---

## Implemented Controls

| NIST Control | Family | Platform Implementation |
|---|---|---|
| AC-2 | Access Control | IAM Identity Center (SSO), Cognito RBAC (Admin/Developer roles) |
| AC-3 | Access Enforcement | SCPs (deny IGW in internal, require WAF in external), RBAC middleware |
| AC-4 | Information Flow | VPC isolation (no cross-VPC routing), private subnets, VPC endpoints |
| AC-6 | Least Privilege | IAM roles scoped to specific resources, PassRole restricted to ECS task roles |
| AC-17 | Remote Access | Client VPN / Direct Connect only for internal; HTTPS for external |
| AU-2 | Audit Events | DynamoDB audit table, CloudWatch Logs, CloudTrail (AWS-managed) |
| AU-3 | Content of Audit Records | Audit entries include: user, timestamp, action, target, outcome |
| AU-6 | Audit Review | Admin Dashboard audit panel, SNS notifications on actions |
| AU-9 | Protection of Audit Info | S3 Object Lock (COMPLIANCE mode, 365-day retention), KMS encryption |
| AU-11 | Audit Retention | CloudWatch Logs: 90 days (non-prod), 365 days (prod); Audit archive: 365 days |
| CA-7 | Continuous Monitoring | Security Hub (FSBP + NIST), GuardDuty, Config rules, Macie |
| CM-2 | Baseline Configuration | Terraform modules define all resource configurations as code |
| CM-3 | Configuration Change Control | Git PR workflow, tfsec + OPA gates, manual approval for prod |
| CM-6 | Configuration Settings | Terraform enforces: read-only FS, non-root user, KMS encryption, tags |
| IA-2 | Identification and Authentication | Okta OIDC → Cognito (dashboard), GitHub OIDC (CI/CD) |
| IA-5 | Authenticator Management | No long-lived credentials; OIDC tokens, Secrets Manager for app secrets |
| IR-4 | Incident Handling | CloudWatch alarms → SNS → Slack, EventBridge for Security Hub findings |
| IR-5 | Incident Monitoring | CloudWatch dashboards, Container Insights, ALB access logs |
| RA-5 | Vulnerability Scanning | Trivy + Inspector + CodeQL in CI/CD, ECR scan-on-push |
| SC-7 | Boundary Protection | VPC isolation, WAF (managed rules + rate limiting), Shield Standard |
| SC-8 | Transmission Confidentiality | TLS 1.3 on all ALBs, HTTPS-only (HTTP redirects to HTTPS) |
| SC-12 | Cryptographic Key Management | KMS CMKs with annual rotation, per-account key isolation |
| SC-13 | Cryptographic Protection | AES-256/KMS encryption for ECR, S3, DynamoDB, CloudWatch Logs, SNS |
| SC-28 | Protection of Information at Rest | All data encrypted with KMS (ECR, S3, DynamoDB, Logs) |
| SI-2 | Flaw Remediation | Scanner gate blocks Critical/High vulnerabilities from deploying |
| SI-4 | Information System Monitoring | GuardDuty, Security Hub, Config, CloudWatch alarms |
| SI-7 | Software Integrity | Container image signing (ECR), immutable image tags (SHA-based) |

---

## Not Applicable for POC (With Rationale)

| NIST Control | Family | Rationale for Exclusion |
|---|---|---|
| AC-11 | Session Lock | Dashboard is a web app; browser session timeout handles this |
| AU-10 | Non-repudiation | Audit trail + Okta identity provides sufficient attribution for POC |
| CP-2 | Contingency Plan | Documented in runbook; formal DR plan is post-POC |
| CP-7 | Alternate Processing Site | Single-region deployment for POC; multi-region is post-POC |
| MA-2 | Controlled Maintenance | Fargate is serverless; no OS patching or maintenance windows |
| MP-2 | Media Access | No physical media; all data is in AWS managed services |
| PE-* | Physical Protection | AWS responsibility under shared responsibility model |
| PL-2 | System Security Plan | This document serves as the initial SSP for POC |
| PS-* | Personnel Security | Organizational control; outside platform scope |
| SA-4 | Acquisition Process | AWS services are FedRAMP authorized; no custom procurement |

---

## Security Hub Standards Enabled

| Standard | ARN |
|---|---|
| AWS Foundational Security Best Practices | `arn:aws:securityhub:us-east-2::standards/aws-foundational-security-best-practices/v/1.0.0` |
| NIST 800-53 Rev 5 | `arn:aws:securityhub:us-east-2::standards/nist-800-53/v/5.0.0` |

Both standards are enabled in the Internal and External accounts via the `modules/security` Terraform module.
