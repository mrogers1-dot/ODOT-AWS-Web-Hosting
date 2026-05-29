# Requirements Document

## Introduction

This document defines the requirements for the Ohio Department of Transportation (ODOT) Web Application Hosting Proof of Concept (POC) on AWS. The solution provisions a modern, secure, fully serverless AWS hosting environment across two dedicated AWS accounts — one for internal (corporate-only) workloads and one for external (public-facing) workloads. Each account hosts three isolated stages (Dev, Test, Prod) using separate VPCs and ECS Fargate clusters. The environment supports automatic CI/CD deployments from GitHub Enterprise, mandatory vulnerability scanning, developer self-service onboarding, infrastructure-as-code via Terraform, and full observability through CloudWatch and Slack notifications.

The POC begins with one application and is designed to scale to hundreds of applications without architectural changes.

---

## Glossary

- **Platform**: The complete ODOT AWS Web Hosting infrastructure, including all accounts, networking, compute, CI/CD, and monitoring components.
- **Internal_Account**: The AWS account `DOT-Web-Internal` (577881328002) used for private, corporate-only web applications accessible only via Client VPN or Direct Connect.
- **External_Account**: The AWS account `DOT-Web-External` (549136075921) used for public-facing web applications accessible over the internet.
- **Stage**: One of three isolated deployment environments — Dev, Test, or Prod — each provisioned in its own VPC within an account.
- **ECS_Cluster**: An Amazon ECS Fargate cluster hosting containerized web application tasks within a given Stage and account.
- **Pipeline**: A GitHub Enterprise Actions CI/CD workflow that builds, scans, and deploys a web application to an ECS_Cluster.
- **Scanner**: The combination of Trivy, Amazon Inspector, and CodeQL used to detect vulnerabilities and code quality issues in container images and source code.
- **App_Template**: The `odot-app-template` GitHub repository template used by developers to bootstrap a new web application with pre-configured CI/CD and infrastructure.
- **ALB**: An AWS Application Load Balancer that distributes traffic to ECS tasks within a Stage.
- **WAF**: AWS Web Application Firewall attached to every ALB in the External_Account.
- **Terraform_Module**: A reusable Terraform configuration unit stored in the `odot-aws-platform` repository that provisions a defined set of AWS resources.
- **SCP**: An AWS Organizations Service Control Policy that enforces account-level guardrails.
- **IaC_Backend**: The Terraform remote state backend using an S3 bucket and DynamoDB table for state locking.
- **Monitoring_Stack**: The combination of CloudWatch Container Insights, dashboards, alarms, SNS topics, AWS Chatbot, and Slack channel integrations.
- **Notification_Channel**: A Slack channel or email address that receives alerts from the Monitoring_Stack.
- **Identity_Center**: AWS IAM Identity Center (SSO) used for federated human access to AWS accounts.
- **KMS_Key**: An AWS KMS Customer Managed Key used to encrypt data at rest.
- **Budget_Alert**: An AWS Budgets notification triggered when projected or actual spend exceeds a defined threshold.
- **OIDC_Connection**: An OpenID Connect trust relationship between GitHub Enterprise and an AWS IAM role, enabling keyless authentication from GitHub Actions.
- **Fargate_Task**: A serverless ECS container instance running on AWS Fargate with no underlying EC2 instance to manage.
- **ECR_Repository**: An Amazon Elastic Container Registry repository that stores Docker images for a web application.
- **Shield_Standard**: AWS Shield Standard DDoS protection automatically applied to all ALBs in the External_Account.
- **Savings_Plan**: An AWS compute commitment that reduces Fargate costs in exchange for consistent usage.
- **Fargate_Spot**: Discounted, interruptible Fargate capacity used in non-production Stages.
- **Container_Insights**: Amazon CloudWatch Container Insights providing CPU, memory, network, and task-level metrics for ECS clusters.
- **Security_Hub**: AWS Security Hub aggregating findings from GuardDuty, Inspector, Config, and Macie into a unified security posture view.
- **GuardDuty**: AWS GuardDuty providing continuous threat detection across accounts.
- **Macie**: AWS Macie providing sensitive data discovery and classification for S3 buckets.
- **Config**: AWS Config providing continuous compliance evaluation of resource configurations.
- **Admin_Dashboard**: The hosted React/Node.js web application providing real-time operational visibility and administrative actions across all platform applications, hosted in the Internal_Account.
- **Cognito_User_Pool**: An Amazon Cognito User Pool federated with Okta that provides authentication and role-based authorization for the Admin_Dashboard.
- **Audit_Table**: A DynamoDB table (`odot-dashboard-audit`) recording all administrative actions performed via the Admin_Dashboard, including user identity, timestamp, action type, and outcome.
- **Maintenance_Mode**: An ALB listener rule configuration that returns a static HTTP 503 maintenance page, toggled via the Admin_Dashboard.

---

## Requirements

### Requirement 1: AWS Account and Organization Structure

**User Story:** As an ODOT infrastructure administrator, I want two dedicated AWS accounts under AWS Organizations with enforced guardrails, so that internal and external workloads are fully isolated and policy-compliant by default.

#### Acceptance Criteria

1. THE Platform SHALL provision two AWS accounts — Internal_Account and External_Account — under a single AWS Organizations structure.
2. THE Platform SHALL attach an SCP to the Internal_Account that denies creation of internet gateways and public-facing resources.
3. THE Platform SHALL attach an SCP to the External_Account that requires WAF to be associated with every ALB before the ALB can serve traffic.
4. WHEN a developer attempts to create an internet gateway in the Internal_Account, THE Platform SHALL deny the action and return an access-denied error.
5. WHEN a developer attempts to create an ALB in the External_Account without an associated WAF, THE Platform SHALL deny the action and return an access-denied error.
6. THE Platform SHALL tag all AWS resources with `Environment`, `Project`, and `Owner` tags as defined in the Terraform_Module for each resource.

---

### Requirement 2: Network Architecture — Internal Account

**User Story:** As an ODOT network engineer, I want private VPCs in the Internal_Account accessible only via Client VPN or Direct Connect, so that internal web applications are never reachable from the public internet.

#### Acceptance Criteria

1. THE Platform SHALL provision three isolated VPCs in the Internal_Account — one per Stage (Dev, Test, Prod).
2. WHILE a Stage is active in the Internal_Account, THE Platform SHALL route all inbound application traffic exclusively through Client VPN or AWS Direct Connect connections.
3. THE Platform SHALL configure each Internal_Account VPC with no internet gateway and no public subnets.
4. THE Platform SHALL provision private subnets across a minimum of two Availability Zones within each Internal_Account VPC.
5. IF a network configuration change would introduce a public route in an Internal_Account VPC, THEN THE Platform SHALL reject the change via SCP enforcement.

---

### Requirement 3: Network Architecture — External Account

**User Story:** As an ODOT network engineer, I want public-facing ALBs protected by WAF and Shield Standard in the External_Account, so that external web applications are accessible to the public while being protected from common web attacks and DDoS threats.

#### Acceptance Criteria

1. THE Platform SHALL provision three isolated VPCs in the External_Account — one per Stage (Dev, Test, Prod).
2. THE Platform SHALL provision public subnets across a minimum of two Availability Zones within each External_Account VPC.
3. THE Platform SHALL attach a WAF Web ACL to every ALB in the External_Account, including ALBs created for new applications onboarded via the App_Template.
4. THE Platform SHALL enable Shield_Standard on all ALBs in the External_Account.
5. WHEN a new ALB is provisioned in the External_Account, THE Platform SHALL automatically associate the WAF Web ACL before the ALB is placed into service.

---

### Requirement 4: Compute — ECS Fargate Clusters

**User Story:** As an ODOT infrastructure administrator, I want one ECS Fargate cluster per Stage per account with multi-AZ redundancy and auto-scaling, so that web applications are highly available and can handle seasonal traffic spikes without manual intervention.

#### Acceptance Criteria

1. THE Platform SHALL provision six ECS_Clusters total — one per Stage (Dev, Test, Prod) in each of the two accounts.
2. THE Platform SHALL configure each ECS_Cluster to run Fargate_Tasks exclusively, with no EC2 launch type permitted.
3. THE Platform SHALL configure each ECS_Cluster to distribute Fargate_Tasks across a minimum of two Availability Zones.
4. THE Platform SHALL configure ECS service auto-scaling for each application with a minimum of 2 Fargate_Tasks and a maximum of 50 Fargate_Tasks per service.
5. WHEN CPU utilization or memory utilization of a Fargate_Task exceeds 70% for 3 consecutive minutes, THE Platform SHALL scale out the ECS service by adding additional Fargate_Tasks.
6. WHEN CPU utilization and memory utilization of all Fargate_Tasks in a service fall below 30% for 10 consecutive minutes, THE Platform SHALL scale in the ECS service by removing Fargate_Tasks, maintaining the minimum of 2.
7. THE Platform SHALL support both Windows containers (IIS/.NET Framework) and Linux containers (.NET, Node.js, Python, Java) within the same ECS_Cluster.
8. THE Platform SHALL configure read-only root filesystems for all Fargate_Tasks.

---

### Requirement 5: Container Image Registry

**User Story:** As an ODOT developer, I want a private ECR repository per application with image scanning enabled, so that only verified, vulnerability-free images are stored and deployed.

#### Acceptance Criteria

1. THE Platform SHALL provision one ECR_Repository per web application per account.
2. THE Platform SHALL enable Amazon ECR image scanning on push for every ECR_Repository.
3. THE Platform SHALL encrypt all images stored in ECR_Repositories using a KMS_Key.
4. WHEN an image is pushed to an ECR_Repository, THE Platform SHALL trigger an Amazon Inspector scan of the image before the image is eligible for deployment.
5. THE Platform SHALL configure ECR lifecycle policies to retain a maximum of 10 tagged images and automatically expire untagged images after 7 days.

---

### Requirement 6: CI/CD Pipeline — Build, Scan, and Deploy

**User Story:** As an ODOT developer, I want an automated CI/CD pipeline that builds, scans, and deploys my application on every push to a branch, so that only secure, tested code reaches each environment without manual steps.

#### Acceptance Criteria

1. THE Pipeline SHALL trigger automatically on every push to the `dev`, `test`, and `prod` branches of an application repository in GitHub Enterprise.
2. THE Pipeline SHALL execute unit tests as the first stage; IF unit tests fail, THEN THE Pipeline SHALL halt and report the failure without proceeding to subsequent stages.
3. THE Pipeline SHALL execute Trivy container image scanning, Amazon Inspector scanning, and CodeQL source code analysis as the second stage.
4. IF the Scanner detects a Critical or High severity vulnerability, THEN THE Pipeline SHALL fail the deployment, prevent the image from being pushed to the ECR_Repository, and report the finding with remediation guidance.
5. WHEN all scans pass, THE Pipeline SHALL build the Docker image and push it to the ECR_Repository tagged with the Git commit SHA and branch name.
6. THE Pipeline SHALL deploy the new image to the corresponding ECS_Cluster Stage using a zero-downtime rolling deployment strategy.
7. THE Pipeline SHALL authenticate to AWS using an OIDC_Connection, with no long-lived AWS credentials stored in GitHub secrets.
8. WHEN a deployment to the Prod Stage is initiated, THE Pipeline SHALL require a manual approval step before applying the ECS service update.
9. THE Pipeline SHALL complete a full build-scan-deploy cycle for a non-Prod Stage within 15 minutes under normal conditions.

---

### Requirement 7: Developer Self-Service Onboarding

**User Story:** As an ODOT developer, I want to onboard a new web application using a GitHub repository template without opening a ticket, so that I can have a fully configured application pipeline running in under 15 minutes.

#### Acceptance Criteria

1. THE Platform SHALL provide the App_Template as a GitHub repository template in the ODOT GitHub Enterprise organization.
2. WHEN a developer creates a new repository from the App_Template, THE App_Template SHALL include pre-configured GitHub Actions workflows, Dockerfile stubs, and Terraform variable files for the new application.
3. WHEN a developer sets the required Terraform variables (application name, runtime, port) and runs `terraform apply`, THE Platform SHALL provision all required AWS resources — ECR_Repository, ECS service, ALB target group, IAM roles, and CloudWatch alarms — for the new application within 15 minutes.
4. THE App_Template SHALL not require the developer to open a ticket, request manual IAM changes, or contact the platform team to complete onboarding.
5. THE Platform SHALL support onboarding from 1 application (POC) to a minimum of 100 applications without architectural changes to the ECS_Clusters or networking layer.
6. THE App_Template SHALL include inline documentation explaining each configuration variable and the expected deployment workflow.

---

### Requirement 8: Infrastructure as Code

**User Story:** As an ODOT infrastructure administrator, I want all AWS resources defined in Terraform modules stored in a central repository, so that the entire environment can be reproduced, audited, or torn down with a single command.

#### Acceptance Criteria

1. THE Platform SHALL define all AWS resources — accounts, VPCs, ECS_Clusters, ALBs, WAF, IAM roles, ECR_Repositories, CloudWatch resources, and security services — as Terraform_Modules in the `odot-aws-platform` repository.
2. THE Platform SHALL use an IaC_Backend consisting of an S3 bucket for state storage and a DynamoDB table for state locking, with versioning enabled on the S3 bucket.
3. WHEN `terraform apply` is executed against the `odot-aws-platform` repository with valid credentials, THE Platform SHALL provision the complete infrastructure for all six ECS_Clusters and supporting resources.
4. WHEN `terraform destroy` is executed against the `odot-aws-platform` repository, THE Platform SHALL remove all provisioned resources without leaving orphaned resources.
5. THE Platform SHALL separate Terraform state files by account and Stage, with one state file per account-Stage combination (e.g., `internal-dev`, `internal-test`, `internal-prod`, `external-dev`, `external-test`, `external-prod`).
6. THE Platform SHALL enforce Terraform module versioning so that changes to a shared module require an explicit version bump before consuming stacks adopt the change.
7. THE Platform SHALL follow the naming convention `{Project}-{Environment}` for all stack and resource group names (e.g., `WebHosting-Prod`).

---

### Requirement 9: Security Controls

**User Story:** As an ODOT security officer, I want comprehensive security controls enabled across both AWS accounts, so that threats are detected, data is encrypted, and access is governed by least-privilege principles.

#### Acceptance Criteria

1. THE Platform SHALL enable GuardDuty in both the Internal_Account and External_Account with findings aggregated to a central Security_Hub.
2. THE Platform SHALL enable Security_Hub in both accounts with the AWS Foundational Security Best Practices standard activated.
3. THE Platform SHALL enable Config in both accounts with rules evaluating compliance of VPC configurations, IAM policies, and ECS task definitions.
4. THE Platform SHALL enable Macie in both accounts to scan S3 buckets for sensitive data.
5. THE Platform SHALL encrypt all data at rest — ECR images, S3 objects, CloudWatch logs, DynamoDB tables — using KMS_Keys with automatic annual key rotation enabled.
6. THE Platform SHALL configure all IAM roles with least-privilege policies, granting only the permissions required for the specific service or pipeline stage.
7. THE Platform SHALL provision human access to both accounts exclusively through Identity_Center with no long-lived IAM user access keys permitted.
8. THE Platform SHALL configure all Fargate_Tasks with read-only root filesystems and non-root user execution.
9. WHEN Security_Hub generates a Critical or High finding, THE Platform SHALL publish the finding to the Monitoring_Stack Notification_Channel within 5 minutes.

---

### Requirement 10: Observability and Monitoring

**User Story:** As an ODOT operations team member, I want CloudWatch dashboards, alarms, and Slack notifications for all environments, so that I can detect and respond to incidents quickly without logging into the AWS console.

#### Acceptance Criteria

1. THE Platform SHALL enable Container_Insights on all six ECS_Clusters to collect CPU, memory, network, and task-level metrics.
2. THE Platform SHALL provision CloudWatch dashboards — one per Stage per account — displaying ECS task count, CPU utilization, memory utilization, ALB request count, ALB 5xx error rate, and active alarm count.
3. THE Platform SHALL configure CloudWatch alarms for the following conditions on each ECS service: CPU utilization above 80% for 5 minutes, memory utilization above 80% for 5 minutes, ALB 5xx error rate above 1% for 5 minutes, and ECS task count below the minimum threshold.
4. WHEN a CloudWatch alarm transitions to the ALARM state, THE Platform SHALL publish a notification to an SNS topic, which routes the alert through AWS Chatbot to the `#aws-alerts-internal` Slack channel for Internal_Account alarms and the `#aws-alerts-external` Slack channel for External_Account alarms.
5. THE Platform SHALL also route alarm notifications to a configured email address for consumption by ServiceNow or FortiSIEM.
6. THE Platform SHALL retain CloudWatch logs for ECS tasks for a minimum of 90 days in non-Prod Stages and 365 days in the Prod Stage.
7. WHEN an ECS task exits unexpectedly, THE Platform SHALL generate a CloudWatch alarm and deliver a notification to the appropriate Notification_Channel within 2 minutes of the exit event.

---

### Requirement 11: Cost Management

**User Story:** As an ODOT finance stakeholder, I want the POC environment to stay under $1,000/month with automated budget alerts, so that cloud spend is visible and controlled from day one.

#### Acceptance Criteria

1. THE Platform SHALL configure AWS Budgets with a monthly cost budget of $1,000 for the POC, covering both the Internal_Account and External_Account combined.
2. WHEN actual or forecasted monthly spend reaches 80% of the budget ($800), THE Platform SHALL send a Budget_Alert notification to the designated email address and Slack channel.
3. THE Platform SHALL apply Fargate_Spot capacity for all ECS services in the Dev and Test Stages to reduce compute costs.
4. THE Platform SHALL apply Savings_Plans to Fargate compute in the Prod Stage to reduce costs relative to on-demand pricing.
5. THE Platform SHALL tag all billable resources with `Environment`, `Project`, and `Owner` tags to enable cost allocation reporting by Stage and application.

---

### Requirement 12: Documentation and Operability

**User Story:** As any ODOT team member, I want clear documentation covering architecture, operations, and onboarding, so that I can understand and operate the system without requiring assistance from the original author.

#### Acceptance Criteria

1. THE Platform SHALL include a README in the `odot-aws-platform` repository describing the overall architecture, account structure, Terraform module layout, and instructions for running `terraform apply` and `terraform destroy`.
2. THE Platform SHALL include a runbook documenting how to: onboard a new application using the App_Template, respond to common CloudWatch alarms, rotate KMS_Keys, and add a new Notification_Channel.
3. THE Platform SHALL include architecture diagrams in the `docs/` directory showing the network topology for both accounts, the CI/CD pipeline flow, and the ECS cluster layout per Stage.
4. THE App_Template SHALL include a `CONTRIBUTING.md` file explaining how developers add new routes, update Dockerfile configurations, and trigger deployments.
5. THE Platform SHALL include inline Terraform comments on all non-obvious resource configurations explaining the purpose and any constraints.

---

### Requirement 13: Implementation Roadmap Milestones

**User Story:** As ODOT senior leadership, I want the POC delivered in four weeks with clear weekly milestones, so that progress is measurable and the demo can be scheduled with confidence.

#### Acceptance Criteria

1. WHEN Week 1 is complete, THE Platform SHALL have the `odot-aws-platform` and `odot-app-template` GitHub repositories created with OIDC_Connections established between GitHub Enterprise and both AWS accounts.
2. WHEN Week 2 is complete, THE Platform SHALL have both AWS accounts provisioned under AWS Organizations with all six VPCs, six ECS_Clusters, ALBs, WAF associations, and SCPs applied.
3. WHEN Week 3 is complete, THE Platform SHALL have the first POC application deployed end-to-end through the Pipeline to all three Stages in both accounts, with the App_Template self-service flow validated.
4. WHEN Week 4 is complete, THE Platform SHALL have all CloudWatch dashboards, alarms, Slack Notification_Channels, email routing, and documentation finalized, with a live demo environment ready for senior leadership review.

---

### Requirement 14: Admin Operations Dashboard

**User Story:** As an ODOT operations team member, I want a hosted web dashboard showing real-time status of all applications across both accounts with drill-down metrics, administrative actions, and manual restart capabilities, so that I can monitor platform health and take corrective action without using the AWS console.

#### Acceptance Criteria

##### Authentication & Authorization

1. THE Admin_Dashboard SHALL authenticate users via Okta (OIDC) federated through a Cognito_User_Pool.
2. THE Admin_Dashboard SHALL enforce two roles mapped from Okta groups: `Developer` (view all, mutating actions on Dev/Test only) and `Admin` (view all, mutating actions on all stages including Prod).
3. WHEN a user without the `Admin` role attempts any mutating action on a Prod service, THE Admin_Dashboard SHALL deny the action and display an "insufficient permissions" message.
4. THE Platform SHALL include documentation covering: Okta App Integration setup (OIDC, authorization code flow), Okta group configuration and user assignment, Cognito federation mapping, and ongoing user/role management procedures.

##### Hosting & Access

5. THE Admin_Dashboard SHALL be hosted as a containerized application (React + Tailwind CSS frontend, Node.js/Express backend API) on ECS Fargate in the Internal_Account, accessible only via Client VPN or Direct Connect.
6. THE Admin_Dashboard SHALL be deployed via the same `app-service` Terraform module and CI/CD Pipeline as other platform applications.

##### Overview Page

7. THE Admin_Dashboard SHALL display a tabbed interface with "Internal" and "External" tabs, each showing a card grid of all applications hosted in that account.
8. EACH application card SHALL display: application name, color-coded status indicator (green=healthy, yellow=degraded, red=down), task health summary (running/desired across stages), and a mini sparkline showing the last 1 hour of health.
9. THE Admin_Dashboard SHALL determine application status as: Healthy (all alarms OK, tasks ≥ desired), Degraded (any warning-level alarm or tasks < desired but > 0), Down (any critical alarm or 0 running tasks).
10. THE Admin_Dashboard SHALL poll for updated status every 30 seconds and display a "last updated" timestamp.

##### Detail Page

11. WHEN a user clicks an application card, THE Admin_Dashboard SHALL navigate to a detail page with sub-tabs for Dev, Test, and Prod stages.
12. THE Detail page SHALL display site metrics: requests per minute, response time (p50, p95, p99), 5xx error rate, 4xx error rate, and active connections — sourced from CloudWatch and ALB metrics.
13. THE Detail page SHALL display app health metrics: running task count vs desired, CPU utilization, memory utilization, last deployment timestamp, task restart count (last 24h), and container image tag.
14. THE Detail page SHALL display user stats: unique source IPs (24h), peak traffic hour, and top request paths — sourced from ALB access logs. (Phase 2: CloudWatch RUM for real user metrics.)
15. THE Detail page SHALL render time-series graphs for request count, latency, CPU/memory utilization, and traffic patterns.

##### Administrative Actions — Service Lifecycle

16. THE Admin_Dashboard SHALL provide the following service lifecycle actions per application per stage: Restart (force new deployment), Stop (set desired count to 0), Start (restore desired count to minimum), Scale Up (increase desired count by N), and Scale Down (decrease desired count by N, floor at minimum).
17. WHEN a user clicks any mutating action button, THE Admin_Dashboard SHALL display a confirmation dialog: "Are you sure you want to {action} {app_name} in {stage}?"
18. THE Admin_Dashboard SHALL log every administrative action to the Audit_Table recording: timestamp, user identity (from Okta/Cognito), application name, stage, action type, parameters, and outcome (success/failure).
19. WHEN any administrative action is executed, THE Admin_Dashboard SHALL publish a notification to the appropriate Slack Notification_Channel: "{user} performed {action} on {app_name} ({stage}) at {timestamp}".

##### Administrative Actions — Diagnostics

20. THE Admin_Dashboard SHALL provide: View Recent Logs (last N lines from CloudWatch Logs), Search Logs (CloudWatch Logs Insights query interface), View Running Tasks (list all tasks with IPs, start time, health status), Stop Specific Task (kill one task — ECS auto-replaces), and Health Check Status (ALB target health per task).
21. THE Admin_Dashboard SHALL provide a View Deployment History panel showing the last 10 deployments with image tag, timestamp, and deployment status.

##### Administrative Actions — Deployment

22. THE Admin_Dashboard SHALL provide a Rollback to Previous Version action that updates the ECS service to use the previous task definition revision.
23. THE Admin_Dashboard SHALL provide a View Available Images panel listing all tagged images in the ECR_Repository with their scan status (clean/vulnerable).

##### Administrative Actions — Traffic & Networking

24. THE Admin_Dashboard SHALL provide an Enable/Disable Maintenance_Mode toggle that configures the ALB listener rule to return a static maintenance page (HTTP 503 with custom HTML body).
25. THE Admin_Dashboard SHALL provide Block IP and Unblock IP actions for External_Account applications that add/remove IP addresses from the WAF IP set.

##### Administrative Actions — Auto-Scaling

26. THE Admin_Dashboard SHALL provide: View Scaling Activity (recent scale events), Temporarily Disable Auto-Scaling (set min=max=current), Re-enable Auto-Scaling (restore original bounds), and Override Min/Max Tasks (temporarily change scaling bounds).

##### Administrative Actions — Configuration

27. THE Admin_Dashboard SHALL provide a View Environment Variables panel showing current task definition environment variables with secret values masked.

##### Role-Based Access Control for Actions

28. THE Admin_Dashboard SHALL enforce: Developers may perform all read-only actions and all mutating actions on Dev and Test stages only. Admins may perform all actions on all stages. Rollback and Block/Unblock IP actions SHALL require the Admin role regardless of stage.

##### Cross-Account Data Access

29. THE Admin_Dashboard's ECS task role SHALL assume a read-only role in the External_Account for querying CloudWatch metrics, ECS service status, and ALB target health.
30. THE Admin_Dashboard's ECS task role SHALL have permission to call mutating ECS, ALB, WAF, and Application Auto Scaling APIs in both accounts, scoped to the specific platform resources.

##### Documentation

31. THE Platform SHALL update `DEPLOYMENT-PREREQUISITES.md` with a new section covering Admin Dashboard setup: Okta configuration, Cognito setup, cross-account IAM roles, DynamoDB audit table, and verification steps.
32. THE Platform SHALL update the `odot-aws-platform` README with the Admin Dashboard module reference, updated repository structure, and architecture description.
33. THE Platform SHALL update `docs/runbook.md` with Admin Dashboard operations: user management, auth troubleshooting, audit log review, and dashboard maintenance.
34. THE Platform SHALL include a new architecture diagram (`docs/architecture/admin-dashboard.md`) showing the Okta → Cognito → Dashboard → AWS API data flow.
35. THE Admin_Dashboard repository SHALL include documentation for: Okta setup (`docs/okta-setup.md`), Cognito setup (`docs/cognito-setup.md`), role management (`docs/role-management.md`), and an admin actions reference (`docs/admin-actions-reference.md`).

---

### Requirement 15: Private Connectivity via VPC Endpoints (Internal Account)

**User Story:** As an ODOT network engineer, I want internal-account Fargate tasks to reach required AWS services without any internet egress, so that workloads remain fully private while still being able to pull images, write logs, and read secrets.

#### Acceptance Criteria

1. THE Platform SHALL provision the following VPC interface endpoints in every Internal_Account VPC: `com.amazonaws.{region}.ecr.api`, `com.amazonaws.{region}.ecr.dkr`, `com.amazonaws.{region}.logs`, `com.amazonaws.{region}.secretsmanager`, `com.amazonaws.{region}.ssm`, `com.amazonaws.{region}.ssmmessages`, and `com.amazonaws.{region}.sts`.
2. THE Platform SHALL provision a `com.amazonaws.{region}.s3` Gateway endpoint in every Internal_Account VPC and associate it with all private route tables (required for ECR image layer retrieval).
3. THE Platform SHALL NOT provision a NAT gateway or internet gateway in any Internal_Account VPC.
4. THE Platform SHALL attach a security group to all interface endpoints that allows inbound HTTPS (443) only from the VPC CIDR block.
5. THE Platform SHALL enable `private_dns_enabled = true` on all interface endpoints so that AWS service DNS names resolve to the endpoint ENIs.
6. WHEN an Internal_Account Fargate task launches, THE Platform SHALL allow the task to pull its image from ECR and write logs to CloudWatch using only the VPC endpoints, with no traffic traversing a public route.
7. THE Platform SHALL provision interface endpoints across the same minimum of two Availability Zones used by the VPC private subnets.

---

### Requirement 16: TLS Termination and DNS

**User Story:** As an ODOT security officer, I want all application traffic encrypted in transit with valid certificates and DNS records, so that no ODOT web application ever serves plaintext HTTP to a user.

#### Acceptance Criteria

1. THE Platform SHALL provision an ACM certificate for each application's fully qualified domain name.
2. THE Platform SHALL configure an HTTPS listener on port 443 for every ALB, using the ACM certificate and a modern TLS security policy (minimum `ELBSecurityPolicy-TLS13-1-2-2021-06`).
3. THE Platform SHALL configure an HTTP listener on port 80 for every ALB that issues a permanent redirect (HTTP 301) to the HTTPS listener.
4. THE Platform SHALL create a Route 53 alias record pointing the application's domain name to its ALB.
5. WHEN a client connects to an ALB over HTTP, THE Platform SHALL redirect the client to the equivalent HTTPS URL before forwarding any request to a Fargate_Task.
6. THE Platform SHALL forward traffic from the ALB to Fargate_Tasks on the container port over the VPC-internal network only.

---

### Requirement 17: ALB Access Logging

**User Story:** As an ODOT operations team member, I want every ALB to record access logs to S3, so that the Admin_Dashboard and security tooling can analyze traffic patterns and source IPs.

#### Acceptance Criteria

1. THE Platform SHALL enable access logging on every ALB, delivering logs to a dedicated S3 bucket.
2. THE Platform SHALL encrypt the ALB access log S3 bucket and block all public access.
3. THE Platform SHALL configure an S3 lifecycle policy that transitions ALB access logs to infrequent-access storage after 30 days and expires them after 365 days.
4. THE Platform SHALL grant the regional ELB service account and the log delivery service permission to write to the access log bucket via a bucket policy.
5. WHEN the Admin_Dashboard requests user statistics (Requirement 14.14), THE Admin_Dashboard SHALL source unique source IPs, peak traffic hour, and top request paths from the ALB access logs.

---

### Requirement 18: WAF Managed Rule Protection

**User Story:** As an ODOT security officer, I want every external WAF Web ACL to enforce managed rule groups and rate limiting, so that public applications are protected against common attacks and volumetric abuse — not merely "associated" with an empty firewall.

#### Acceptance Criteria

1. THE Platform SHALL configure every External_Account WAF Web ACL with the AWS Managed Rule group `AWSManagedRulesCommonRuleSet`.
2. THE Platform SHALL configure every External_Account WAF Web ACL with the AWS Managed Rule group `AWSManagedRulesKnownBadInputsRuleSet`.
3. THE Platform SHALL configure every External_Account WAF Web ACL with the AWS Managed Rule group `AWSManagedRulesSQLiRuleSet`.
4. THE Platform SHALL configure a rate-based rule on every External_Account WAF Web ACL that blocks a source IP exceeding 2,000 requests in any 5-minute window.
5. THE Platform SHALL enable WAF logging to CloudWatch Logs for every Web ACL.
6. THE Platform SHALL set the default action of every WAF Web ACL to `allow`, so that only requests matching block rules are rejected.

---

### Requirement 19: Compliance Framework Alignment

**User Story:** As an ODOT security officer, I want the platform's security posture mapped to a recognized control framework, so that the environment is audit-ready for state-government compliance review.

#### Acceptance Criteria

1. THE Platform SHALL enable the `NIST Special Publication 800-53 Revision 5` standard in Security_Hub in both accounts, in addition to the AWS Foundational Security Best Practices standard.
2. THE Platform SHALL include a compliance mapping document that maps each implemented security control to its corresponding NIST 800-53 control family.
3. THE Platform SHALL document, for each Security_Hub control that is intentionally not applicable to the POC, the rationale for its exclusion.

---

### Requirement 20: Secrets Management

**User Story:** As an ODOT security officer, I want all third-party credentials stored in a managed secrets store rather than in Terraform state or variables, so that no secret material is exposed in version control or plan output.

#### Acceptance Criteria

1. THE Platform SHALL store the Okta OIDC client secret in AWS Secrets Manager, encrypted with a KMS_Key.
2. THE admin-dashboard Terraform_Module SHALL read the Okta client secret from Secrets Manager at apply time rather than accepting it as a plaintext variable value committed to version control.
3. THE Platform SHALL grant the Cognito and Admin_Dashboard task roles read access to only the specific secret ARNs they require.
4. THE Platform SHALL NOT write any secret value to Terraform state in plaintext.

---

### Requirement 21: Infrastructure Code Scanning and Policy as Code

**User Story:** As an ODOT security officer, I want the platform's own Terraform scanned and policy-checked in CI before apply, so that the infrastructure that enforces our guardrails is itself verified secure.

#### Acceptance Criteria

1. THE Platform SHALL run a static analysis scanner (tfsec or Checkov) against all Terraform_Modules in the `odot-aws-platform` CI pipeline on every pull request.
2. IF the static analysis scanner detects a HIGH or CRITICAL severity misconfiguration, THEN THE Platform SHALL fail the pull request check and block merge.
3. THE Platform SHALL run a policy-as-code evaluation (OPA/Conftest) against the rendered `terraform plan` output that asserts platform invariants: all resources are tagged, no security group allows `0.0.0.0/0` ingress except external ALBs on 443, and all storage is encrypted.
4. WHEN a policy-as-code assertion fails, THE Platform SHALL block the pull request and report which policy was violated.

---

### Requirement 22: Tag Governance

**User Story:** As an ODOT infrastructure administrator, I want untagged resources prevented at the organization level, so that cost allocation and ownership are guaranteed rather than merely encouraged.

#### Acceptance Criteria

1. THE Platform SHALL define an AWS Organizations Tag Policy that requires the `Environment`, `Project`, and `Owner` tags on all taggable resource types.
2. THE Platform SHALL attach the Tag Policy to the organizational unit containing the Internal_Account and External_Account.
3. THE Platform SHALL define the allowed values for the `Environment` tag as exactly `dev`, `test`, and `prod`.

---

### Requirement 23: Resilience Validation

**User Story:** As an ODOT operations team member, I want automated fault-injection experiments that prove the platform recovers from failures, so that high-availability claims are backed by evidence rather than assumption.

#### Acceptance Criteria

1. THE Platform SHALL define an AWS Fault Injection Simulator experiment template that stops a percentage of a service's Fargate_Tasks in a single Availability Zone.
2. WHEN the fault-injection experiment runs against a service with the minimum 2 tasks, THE Platform SHALL restore the desired task count within 5 minutes without manual intervention.
3. THE Platform SHALL define a fault-injection experiment that simulates a failed deployment and asserts the ECS deployment circuit breaker rolls back to the last healthy task definition.
4. THE Platform SHALL document the fault-injection experiments and their expected recovery behavior in the runbook.

---

### Requirement 24: Application Scaling Model

**User Story:** As an ODOT infrastructure administrator, I want a documented, tested model for hosting hundreds of applications, so that the platform scales without hitting account limits or unbounded cost.

#### Acceptance Criteria

1. THE Platform SHALL document the load-balancer scaling model, explicitly choosing between shared-ALB-with-host-routing and ALB-per-application, with the rationale and tradeoffs stated.
2. THE Platform SHALL document the relevant AWS Service Quotas (ALBs per region, target groups per ALB, listener rules per ALB, ECS services per cluster) and the threshold at which a quota increase must be requested.
3. THE Platform SHALL provide a capacity-planning calculation showing the theoretical maximum number of applications supportable under the chosen model before any quota increase is required.

---

### Requirement 25: Synthetic Monitoring and Service Level Objectives

**User Story:** As an ODOT operations team member, I want synthetic canaries and defined SLOs for each application, so that availability problems are detected proactively before users report them.

#### Acceptance Criteria

1. THE Platform SHALL provision a CloudWatch Synthetics canary for each application endpoint that issues a request at a configurable interval (default 5 minutes).
2. WHEN a canary detects a non-2xx/3xx response or a timeout, THE Platform SHALL transition a canary alarm to ALARM and notify the appropriate Notification_Channel.
3. THE Platform SHALL define a default Service Level Objective of 99.9% successful requests measured over a rolling 30-day window for Prod applications.
4. THE Platform SHALL surface the SLO attainment and remaining error budget on the Admin_Dashboard detail page.

---

### Requirement 26: Distributed Tracing

**User Story:** As an ODOT developer, I want request-level distributed tracing across services, so that performance bottlenecks can be isolated to a specific service or dependency.

#### Acceptance Criteria

1. THE Platform SHALL provide an AWS Distro for OpenTelemetry (ADOT) sidecar container definition that application task definitions can include.
2. THE Platform SHALL configure the ADOT sidecar to export traces to AWS X-Ray.
3. THE Platform SHALL grant Fargate_Tasks the IAM permissions required to write trace segments to X-Ray.
4. THE App_Template SHALL document how a developer enables tracing for their application.

---

### Requirement 27: Real-Time Dashboard Updates

**User Story:** As an ODOT operations team member, I want the Admin_Dashboard to update in real time rather than on a fixed poll interval, so that I see status changes the moment they happen during an incident.

#### Acceptance Criteria

1. THE Admin_Dashboard SHALL push status updates to connected clients using Server-Sent Events (SSE) or WebSockets rather than relying solely on 30-second polling.
2. WHEN an application's status changes (healthy/degraded/down), THE Admin_Dashboard SHALL deliver the updated status to connected clients within 10 seconds of the change.
3. IF the real-time channel disconnects, THEN THE Admin_Dashboard SHALL fall back to 30-second polling and display a "reconnecting" indicator.
4. THE Admin_Dashboard SHALL continue to display the "last updated" timestamp reflecting the most recent successful update.

---

### Requirement 28: Tamper-Evident Audit Trail

**User Story:** As an ODOT security officer, I want the Admin_Dashboard audit trail exported to immutable storage, so that the record of who did what cannot be altered or deleted, even by an administrator.

#### Acceptance Criteria

1. THE Platform SHALL export Audit_Table records to an S3 bucket configured with Object Lock in compliance mode.
2. THE Platform SHALL set a retention period of a minimum of 365 days on the Object Lock configuration of the audit export bucket.
3. THE Platform SHALL run the audit export on a scheduled basis (minimum daily) via an EventBridge-scheduled task.
4. THE Platform SHALL NOT grant any IAM principal permission to delete or overwrite objects in the audit export bucket before the Object Lock retention period expires.
