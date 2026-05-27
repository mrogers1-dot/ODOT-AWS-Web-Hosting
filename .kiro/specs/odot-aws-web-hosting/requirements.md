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
